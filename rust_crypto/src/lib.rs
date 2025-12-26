use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use rayon::prelude::*;
use sha2::{Digest, Sha256};
use std::slice;
use std::sync::Arc;
use std::fs::File;
use std::io::{Read, Write, BufReader, BufWriter, Seek, SeekFrom};
use std::ffi::CStr;
use std::os::raw::c_char;
use rand::RngCore;

const NONCE_SIZE: usize = 12;
const TAG_SIZE: usize = 16;
const MAGIC_STRING: &[u8] = b"KYRIE_LOCK";
const VERSION: u32 = 1;
const HEADER_SIZE: usize = 14;
const MAX_HINT_LENGTH: usize = 32;

fn derive_key(password: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(password);
    let result = hasher.finalize();
    let mut key = [0u8; 32];
    key.copy_from_slice(&result);
    key
}

fn get_chunk_size(is_mobile: bool) -> usize {
    if is_mobile {
        128 * 1024 * 1024
    } else {
        256 * 1024 * 1024
    }
}

fn get_parallel_batch_threshold(is_mobile: bool) -> usize {
    if is_mobile {
        512 * 1024 * 1024
    } else {
        1024 * 1024 * 1024
    }
}

fn get_parallel_batch_size(cpu_cores: usize, is_mobile: bool) -> usize {
    if is_mobile {
        ((cpu_cores as f32 * 0.5).round() as usize).clamp(2, 8)
    } else {
        ((cpu_cores as f32 * 0.75).round() as usize).clamp(4, 16)
    }
}

fn generate_nonce() -> [u8; NONCE_SIZE] {
    let mut nonce = [0u8; NONCE_SIZE];
    rand::thread_rng().fill_bytes(&mut nonce);
    nonce
}

#[no_mangle]
pub extern "C" fn encrypt_file(
    input_path_ptr: *const c_char,
    output_path_ptr: *const c_char,
    password_ptr: *const u8,
    password_len: usize,
    hint_ptr: *const c_char,
    is_mobile: bool,
    cpu_cores: usize,
) -> i32 {
    unsafe {
        let input_path = match CStr::from_ptr(input_path_ptr).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let output_path = match CStr::from_ptr(output_path_ptr).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let password = slice::from_raw_parts(password_ptr, password_len);
        let hint = if hint_ptr.is_null() {
            None
        } else {
            CStr::from_ptr(hint_ptr).to_str().ok()
        };

        match encrypt_file_internal(input_path, output_path, password, hint, is_mobile, cpu_cores) {
            Ok(_) => 0,
            Err(_) => -2,
        }
    }
}

fn encrypt_file_internal(
    input_path: &str,
    output_path: &str,
    password: &[u8],
    hint: Option<&str>,
    is_mobile: bool,
    cpu_cores: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    let chunk_size = get_chunk_size(is_mobile);
    let parallel_threshold = get_parallel_batch_threshold(is_mobile);
    let batch_size = get_parallel_batch_size(cpu_cores, is_mobile);
    
    let input_file = File::open(input_path)?;
    let file_size = input_file.metadata()?.len() as usize;
    
    let mut output_file = BufWriter::new(File::create(output_path)?);
    
    let hint_bytes = hint
        .map(|h| h.as_bytes())
        .unwrap_or(&[])
        .iter()
        .take(MAX_HINT_LENGTH)
        .copied()
        .collect::<Vec<u8>>();
    let hint_len = hint_bytes.len() as u8;
    
    output_file.write_all(MAGIC_STRING)?;
    output_file.write_all(&VERSION.to_le_bytes())?;
    output_file.write_all(&[hint_len])?;
    output_file.write_all(&hint_bytes)?;
    
    let key = derive_key(password);
    let cipher = Aes256Gcm::new_from_slice(&key)?;
    
    if file_size <= chunk_size {
        let nonce_bytes = generate_nonce();
        output_file.write_all(&nonce_bytes)?;
        
        let mut data = Vec::new();
        let mut reader = BufReader::new(input_file);
        reader.read_to_end(&mut data)?;
        
        let nonce = Nonce::from_slice(&nonce_bytes);
        let encrypted = cipher.encrypt(nonce, data.as_ref())
            .map_err(|_| "Encryption failed")?;
        output_file.write_all(&encrypted)?;
    } else if file_size <= parallel_threshold {
        let mut all_data = Vec::new();
        let mut reader = BufReader::new(input_file);
        reader.read_to_end(&mut all_data)?;
        
        let mut chunks = Vec::new();
        let mut nonces = Vec::new();
        
        for chunk in all_data.chunks(chunk_size) {
            chunks.push(chunk.to_vec());
            nonces.push(generate_nonce());
        }
        
        let key_arc = Arc::new(key);
        let encrypted_chunks: Result<Vec<Vec<u8>>, &str> = chunks
            .par_iter()
            .zip(nonces.par_iter())
            .map(|(chunk, nonce_bytes)| {
                let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                    .map_err(|_| "Invalid key")?;
                let nonce = Nonce::from_slice(nonce_bytes);
                cipher.encrypt(nonce, chunk.as_ref())
                    .map_err(|_| "Encryption failed")
            })
            .collect();
        
        let encrypted_chunks = encrypted_chunks?;
        
        for (encrypted, nonce_bytes) in encrypted_chunks.iter().zip(nonces.iter()) {
            output_file.write_all(nonce_bytes)?;
            output_file.write_all(&(encrypted.len() as u32).to_be_bytes())?;
            output_file.write_all(encrypted)?;
        }
    } else {
        let mut reader = BufReader::new(input_file);
        let key_arc = Arc::new(key);
        
        loop {
            let mut chunks = Vec::new();
            let mut nonces = Vec::new();
            
            for _ in 0..batch_size {
                let mut chunk = vec![0u8; chunk_size];
                match reader.read(&mut chunk)? {
                    0 => break,
                    n => {
                        chunk.truncate(n);
                        chunks.push(chunk);
                        nonces.push(generate_nonce());
                    }
                }
            }
            
            if chunks.is_empty() {
                break;
            }
            
            let encrypted_chunks: Result<Vec<Vec<u8>>, &str> = chunks
                .par_iter()
                .zip(nonces.par_iter())
                .map(|(chunk, nonce_bytes)| {
                    let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                        .map_err(|_| "Invalid key")?;
                    let nonce = Nonce::from_slice(nonce_bytes);
                    cipher.encrypt(nonce, chunk.as_ref())
                        .map_err(|_| "Encryption failed")
                })
                .collect();
            
            let encrypted_chunks = encrypted_chunks?;
            
            for (encrypted, nonce_bytes) in encrypted_chunks.iter().zip(nonces.iter()) {
                output_file.write_all(nonce_bytes)?;
                output_file.write_all(&(encrypted.len() as u32).to_be_bytes())?;
                output_file.write_all(encrypted)?;
            }
        }
    }
    
    output_file.flush()?;
    Ok(())
}

#[no_mangle]
pub extern "C" fn decrypt_file(
    input_path_ptr: *const c_char,
    output_path_ptr: *const c_char,
    password_ptr: *const u8,
    password_len: usize,
    is_mobile: bool,
    cpu_cores: usize,
) -> i32 {
    unsafe {
        let input_path = match CStr::from_ptr(input_path_ptr).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let output_path = match CStr::from_ptr(output_path_ptr).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let password = slice::from_raw_parts(password_ptr, password_len);

        match decrypt_file_internal(input_path, output_path, password, is_mobile, cpu_cores) {
            Ok(_) => 0,
            Err(_) => -2,
        }
    }
}

fn decrypt_file_internal(
    input_path: &str,
    output_path: &str,
    password: &[u8],
    is_mobile: bool,
    cpu_cores: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    let chunk_size = get_chunk_size(is_mobile);
    let parallel_threshold = get_parallel_batch_threshold(is_mobile);
    let batch_size = get_parallel_batch_size(cpu_cores, is_mobile);
    
    let mut input_file = BufReader::new(File::open(input_path)?);
    
    let mut magic = vec![0u8; MAGIC_STRING.len()];
    input_file.read_exact(&mut magic)?;
    if magic != MAGIC_STRING {
        return Err("Invalid file format".into());
    }
    
    let mut version_bytes = [0u8; 4];
    input_file.read_exact(&mut version_bytes)?;
    let version = u32::from_le_bytes(version_bytes);
    if version != VERSION {
        return Err("Unsupported version".into());
    }
    
    let mut hint_len_bytes = [0u8; 1];
    input_file.read_exact(&mut hint_len_bytes)?;
    let hint_len = hint_len_bytes[0] as usize;
    
    let mut hint_bytes = vec![0u8; hint_len];
    input_file.read_exact(&mut hint_bytes)?;
    
    let encrypted_data_start = HEADER_SIZE + 1 + hint_len;
    
    let file_size = std::fs::metadata(input_path)?.len() as usize;
    let encrypted_size = file_size - encrypted_data_start;
    
    let key = derive_key(password);
    let cipher = Aes256Gcm::new_from_slice(&key)?;
    
    let mut output_file = BufWriter::new(File::create(output_path)?);
    
    let is_single_chunk = {
        let mut temp_nonce = [0u8; NONCE_SIZE];
        input_file.read_exact(&mut temp_nonce)?;
        
        let remaining = encrypted_size - NONCE_SIZE;
        let is_single = remaining <= (chunk_size + TAG_SIZE);
        
        input_file.seek(SeekFrom::Start(encrypted_data_start as u64))?;
        is_single
    };
    
    if is_single_chunk {
        let mut nonce_bytes = [0u8; NONCE_SIZE];
        input_file.read_exact(&mut nonce_bytes)?;
        
        let mut encrypted_data = Vec::new();
        input_file.read_to_end(&mut encrypted_data)?;
        
        let nonce = Nonce::from_slice(&nonce_bytes);
        let decrypted = cipher.decrypt(nonce, encrypted_data.as_ref())
            .map_err(|_| "Decryption failed")?;
        
        output_file.write_all(&decrypted)?;
    } else if encrypted_size <= parallel_threshold {
        let mut chunks = Vec::new();
        let mut nonces = Vec::new();
        
        while let Ok(nonce_bytes) = {
            let mut buf = [0u8; NONCE_SIZE];
            input_file.read_exact(&mut buf).map(|_| buf)
        } {
            let mut chunk_len_bytes = [0u8; 4];
            if input_file.read_exact(&mut chunk_len_bytes).is_err() {
                break;
            }
            let chunk_len = u32::from_be_bytes(chunk_len_bytes) as usize;
            
            let mut encrypted_chunk = vec![0u8; chunk_len];
            input_file.read_exact(&mut encrypted_chunk)?;
            
            chunks.push(encrypted_chunk);
            nonces.push(nonce_bytes);
        }
        
        let key_arc = Arc::new(key);
        let decrypted_chunks: Result<Vec<Vec<u8>>, &str> = chunks
            .par_iter()
            .zip(nonces.par_iter())
            .map(|(chunk, nonce_bytes)| {
                let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                    .map_err(|_| "Invalid key")?;
                let nonce = Nonce::from_slice(nonce_bytes);
                cipher.decrypt(nonce, chunk.as_ref())
                    .map_err(|_| "Decryption failed")
            })
            .collect();
        
        let decrypted_chunks = decrypted_chunks?;
        
        for decrypted in decrypted_chunks.iter() {
            output_file.write_all(decrypted)?;
        }
    } else {
        let key_arc = Arc::new(key);
        
        loop {
            let mut chunks = Vec::new();
            let mut nonces = Vec::new();
            
            for _ in 0..batch_size {
                let mut nonce_bytes = [0u8; NONCE_SIZE];
                if input_file.read_exact(&mut nonce_bytes).is_err() {
                    break;
                }
                
                let mut chunk_len_bytes = [0u8; 4];
                if input_file.read_exact(&mut chunk_len_bytes).is_err() {
                    break;
                }
                let chunk_len = u32::from_be_bytes(chunk_len_bytes) as usize;
                
                let mut encrypted_chunk = vec![0u8; chunk_len];
                if input_file.read_exact(&mut encrypted_chunk).is_err() {
                    break;
                }
                
                chunks.push(encrypted_chunk);
                nonces.push(nonce_bytes);
            }
            
            if chunks.is_empty() {
                break;
            }
            
            let decrypted_chunks: Result<Vec<Vec<u8>>, &str> = chunks
                .par_iter()
                .zip(nonces.par_iter())
                .map(|(chunk, nonce_bytes)| {
                    let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                        .map_err(|_| "Invalid key")?;
                    let nonce = Nonce::from_slice(nonce_bytes);
                    cipher.decrypt(nonce, chunk.as_ref())
                        .map_err(|_| "Decryption failed")
                })
                .collect();
            
            let decrypted_chunks = decrypted_chunks?;
            
            for decrypted in decrypted_chunks.iter() {
                output_file.write_all(decrypted)?;
            }
        }
    }
    
    output_file.flush()?;
    Ok(())
}

#[no_mangle]
pub extern "C" fn decrypt_file_to_memory(
    input_path_ptr: *const c_char,
    password_ptr: *const u8,
    password_len: usize,
    output_ptr: *mut u8,
    output_len: *mut usize,
    is_mobile: bool,
    cpu_cores: usize,
) -> i32 {
    unsafe {
        let input_path = match CStr::from_ptr(input_path_ptr).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let password = slice::from_raw_parts(password_ptr, password_len);

        match decrypt_file_to_memory_internal(input_path, password, is_mobile, cpu_cores) {
            Ok(data) => {
                *output_len = data.len();
                if !output_ptr.is_null() {
                    std::ptr::copy_nonoverlapping(data.as_ptr(), output_ptr, data.len());
                }
                0
            }
            Err(_) => -2,
        }
    }
}

fn decrypt_file_to_memory_internal(
    input_path: &str,
    password: &[u8],
    is_mobile: bool,
    _cpu_cores: usize,
) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let chunk_size = get_chunk_size(is_mobile);
    let _parallel_threshold = get_parallel_batch_threshold(is_mobile);
    
    let mut input_file = BufReader::new(File::open(input_path)?);
    
    let mut magic = vec![0u8; MAGIC_STRING.len()];
    input_file.read_exact(&mut magic)?;
    if magic != MAGIC_STRING {
        return Err("Invalid file format".into());
    }
    
    let mut version_bytes = [0u8; 4];
    input_file.read_exact(&mut version_bytes)?;
    let version = u32::from_le_bytes(version_bytes);
    if version != VERSION {
        return Err("Unsupported version".into());
    }
    
    let mut hint_len_bytes = [0u8; 1];
    input_file.read_exact(&mut hint_len_bytes)?;
    let hint_len = hint_len_bytes[0] as usize;
    
    let mut hint_bytes = vec![0u8; hint_len];
    input_file.read_exact(&mut hint_bytes)?;
    
    let encrypted_data_start = HEADER_SIZE + 1 + hint_len;
    
    let file_size = std::fs::metadata(input_path)?.len() as usize;
    let encrypted_size = file_size - encrypted_data_start;
    
    let key = derive_key(password);
    let cipher = Aes256Gcm::new_from_slice(&key)?;
    
    let is_single_chunk = {
        let mut temp_nonce = [0u8; NONCE_SIZE];
        input_file.read_exact(&mut temp_nonce)?;
        
        let remaining = encrypted_size - NONCE_SIZE;
        let is_single = remaining <= (chunk_size + TAG_SIZE);
        
        input_file.seek(SeekFrom::Start(encrypted_data_start as u64))?;
        is_single
    };
    
    if is_single_chunk {
        let mut nonce_bytes = [0u8; NONCE_SIZE];
        input_file.read_exact(&mut nonce_bytes)?;
        
        let mut encrypted_data = Vec::new();
        input_file.read_to_end(&mut encrypted_data)?;
        
        let nonce = Nonce::from_slice(&nonce_bytes);
        let decrypted = cipher.decrypt(nonce, encrypted_data.as_ref())
            .map_err(|_| "Decryption failed")?;
        
        Ok(decrypted)
    } else {
        let mut chunks = Vec::new();
        let mut nonces = Vec::new();
        
        while let Ok(nonce_bytes) = {
            let mut buf = [0u8; NONCE_SIZE];
            input_file.read_exact(&mut buf).map(|_| buf)
        } {
            let mut chunk_len_bytes = [0u8; 4];
            if input_file.read_exact(&mut chunk_len_bytes).is_err() {
                break;
            }
            let chunk_len = u32::from_be_bytes(chunk_len_bytes) as usize;
            
            let mut encrypted_chunk = vec![0u8; chunk_len];
            input_file.read_exact(&mut encrypted_chunk)?;
            
            chunks.push(encrypted_chunk);
            nonces.push(nonce_bytes);
        }
        
        let key_arc = Arc::new(key);
        let decrypted_chunks: Result<Vec<Vec<u8>>, &str> = chunks
            .par_iter()
            .zip(nonces.par_iter())
            .map(|(chunk, nonce_bytes)| {
                let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                    .map_err(|_| "Invalid key")?;
                let nonce = Nonce::from_slice(nonce_bytes);
                cipher.decrypt(nonce, chunk.as_ref())
                    .map_err(|_| "Decryption failed")
            })
            .collect();
        
        let decrypted_chunks = decrypted_chunks?;
        
        let mut result = Vec::new();
        for decrypted in decrypted_chunks.iter() {
            result.extend_from_slice(decrypted);
        }
        
        Ok(result)
    }
}

#[no_mangle]
pub extern "C" fn get_hint_from_file(
    input_path_ptr: *const c_char,
    hint_ptr: *mut u8,
    hint_len: *mut usize,
) -> i32 {
    unsafe {
        let input_path = match CStr::from_ptr(input_path_ptr).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };

        match get_hint_from_file_internal(input_path) {
            Ok(hint_bytes) => {
                *hint_len = hint_bytes.len();
                if !hint_ptr.is_null() {
                    std::ptr::copy_nonoverlapping(hint_bytes.as_ptr(), hint_ptr, hint_bytes.len());
                }
                0
            }
            Err(_) => -2,
        }
    }
}

fn get_hint_from_file_internal(input_path: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let mut input_file = File::open(input_path)?;
    
    let mut magic = vec![0u8; MAGIC_STRING.len()];
    input_file.read_exact(&mut magic)?;
    if magic != MAGIC_STRING {
        return Err("Invalid file format".into());
    }
    
    let mut version_bytes = [0u8; 4];
    input_file.read_exact(&mut version_bytes)?;
    
    let mut hint_len_bytes = [0u8; 1];
    input_file.read_exact(&mut hint_len_bytes)?;
    let hint_len = hint_len_bytes[0] as usize;
    
    let mut hint_bytes = vec![0u8; hint_len];
    input_file.read_exact(&mut hint_bytes)?;
    
    Ok(hint_bytes)
}

#[no_mangle]
pub extern "C" fn encrypt_data_parallel(
    chunks_ptr: *const *const u8,
    chunk_lens: *const usize,
    num_chunks: usize,
    password_ptr: *const u8,
    password_len: usize,
    nonces_ptr: *const u8,
    outputs_ptr: *mut *mut u8,
    output_lens: *mut usize,
) -> i32 {
    unsafe {
        let password = slice::from_raw_parts(password_ptr, password_len);
        let key = derive_key(password);
        let key_arc = Arc::new(key);
        
        let chunk_ptrs = slice::from_raw_parts(chunks_ptr, num_chunks);
        let chunk_lengths = slice::from_raw_parts(chunk_lens, num_chunks);
        let nonces = slice::from_raw_parts(nonces_ptr, num_chunks * NONCE_SIZE);
        
        let chunks: Vec<&[u8]> = chunk_ptrs
            .iter()
            .zip(chunk_lengths.iter())
            .map(|(ptr, len)| slice::from_raw_parts(*ptr, *len))
            .collect();
        
        let results: Result<Vec<Vec<u8>>, i32> = chunks
            .par_iter()
            .enumerate()
            .map(|(i, chunk)| {
                let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                    .map_err(|_| -1)?;
                
                let nonce_offset = i * NONCE_SIZE;
                let nonce = Nonce::from_slice(&nonces[nonce_offset..nonce_offset + NONCE_SIZE]);
                
                cipher.encrypt(nonce, chunk.as_ref())
                    .map_err(|_| -2)
            })
            .collect();
        
        match results {
            Ok(encrypted_chunks) => {
                let output_lens_slice = slice::from_raw_parts_mut(output_lens, num_chunks);
                let outputs_slice = slice::from_raw_parts_mut(outputs_ptr, num_chunks);
                
                for (i, encrypted) in encrypted_chunks.iter().enumerate() {
                    output_lens_slice[i] = encrypted.len();
                    if !outputs_slice[i].is_null() {
                        std::ptr::copy_nonoverlapping(
                            encrypted.as_ptr(),
                            outputs_slice[i],
                            encrypted.len(),
                        );
                    }
                }
                0
            }
            Err(code) => code,
        }
    }
}

#[no_mangle]
pub extern "C" fn decrypt_data_parallel(
    chunks_ptr: *const *const u8,
    chunk_lens: *const usize,
    num_chunks: usize,
    password_ptr: *const u8,
    password_len: usize,
    nonces_ptr: *const u8,
    outputs_ptr: *mut *mut u8,
    output_lens: *mut usize,
) -> i32 {
    unsafe {
        let password = slice::from_raw_parts(password_ptr, password_len);
        let key = derive_key(password);
        let key_arc = Arc::new(key);
        
        let chunk_ptrs = slice::from_raw_parts(chunks_ptr, num_chunks);
        let chunk_lengths = slice::from_raw_parts(chunk_lens, num_chunks);
        let nonces = slice::from_raw_parts(nonces_ptr, num_chunks * NONCE_SIZE);
        
        let chunks: Vec<&[u8]> = chunk_ptrs
            .iter()
            .zip(chunk_lengths.iter())
            .map(|(ptr, len)| slice::from_raw_parts(*ptr, *len))
            .collect();
        
        let results: Result<Vec<Vec<u8>>, i32> = chunks
            .par_iter()
            .enumerate()
            .map(|(i, chunk)| {
                let cipher = Aes256Gcm::new_from_slice(&*key_arc)
                    .map_err(|_| -1)?;
                
                let nonce_offset = i * NONCE_SIZE;
                let nonce = Nonce::from_slice(&nonces[nonce_offset..nonce_offset + NONCE_SIZE]);
                
                cipher.decrypt(nonce, chunk.as_ref())
                    .map_err(|_| -2)
            })
            .collect();
        
        match results {
            Ok(decrypted_chunks) => {
                let output_lens_slice = slice::from_raw_parts_mut(output_lens, num_chunks);
                let outputs_slice = slice::from_raw_parts_mut(outputs_ptr, num_chunks);
                
                for (i, decrypted) in decrypted_chunks.iter().enumerate() {
                    output_lens_slice[i] = decrypted.len();
                    if !outputs_slice[i].is_null() {
                        std::ptr::copy_nonoverlapping(
                            decrypted.as_ptr(),
                            outputs_slice[i],
                            decrypted.len(),
                        );
                    }
                }
                0
            }
            Err(code) => code,
        }
    }
}

#[no_mangle]
pub extern "C" fn encrypt_data(
    data_ptr: *const u8,
    data_len: usize,
    password_ptr: *const u8,
    password_len: usize,
    nonce_ptr: *const u8,
    output_ptr: *mut u8,
    output_len: *mut usize,
) -> i32 {
    unsafe {
        let data = slice::from_raw_parts(data_ptr, data_len);
        let password = slice::from_raw_parts(password_ptr, password_len);
        let nonce_bytes = slice::from_raw_parts(nonce_ptr, NONCE_SIZE);
        
        let key = derive_key(password);
        let cipher = match Aes256Gcm::new_from_slice(&key) {
            Ok(c) => c,
            Err(_) => return -1,
        };
        
        let nonce = Nonce::from_slice(nonce_bytes);
        
        let encrypted = match cipher.encrypt(nonce, data) {
            Ok(e) => e,
            Err(_) => return -2,
        };
        
        *output_len = encrypted.len();
        
        if !output_ptr.is_null() {
            std::ptr::copy_nonoverlapping(encrypted.as_ptr(), output_ptr, encrypted.len());
        }
        
        0
    }
}

#[no_mangle]
pub extern "C" fn decrypt_data(
    encrypted_ptr: *const u8,
    encrypted_len: usize,
    password_ptr: *const u8,
    password_len: usize,
    nonce_ptr: *const u8,
    output_ptr: *mut u8,
    output_len: *mut usize,
) -> i32 {
    unsafe {
        let encrypted = slice::from_raw_parts(encrypted_ptr, encrypted_len);
        let password = slice::from_raw_parts(password_ptr, password_len);
        let nonce_bytes = slice::from_raw_parts(nonce_ptr, NONCE_SIZE);
        
        let key = derive_key(password);
        let cipher = match Aes256Gcm::new_from_slice(&key) {
            Ok(c) => c,
            Err(_) => return -1,
        };
        
        let nonce = Nonce::from_slice(nonce_bytes);
        
        let decrypted = match cipher.decrypt(nonce, encrypted) {
            Ok(d) => d,
            Err(_) => return -2,
        };
        
        *output_len = decrypted.len();
        
        if !output_ptr.is_null() {
            std::ptr::copy_nonoverlapping(decrypted.as_ptr(), output_ptr, decrypted.len());
        }
        
        0
    }
}

#[no_mangle]
pub extern "C" fn derive_key_ffi(
    password_ptr: *const u8,
    password_len: usize,
    output_ptr: *mut u8,
) -> i32 {
    unsafe {
        let password = slice::from_raw_parts(password_ptr, password_len);
        let key = derive_key(password);
        std::ptr::copy_nonoverlapping(key.as_ptr(), output_ptr, 32);
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_key() {
        let password = b"test_password";
        let key = derive_key(password);
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn test_encrypt_decrypt() {
        let data = b"Hello, World! This is a test message.";
        let password = b"secure_password";
        let nonce = [0u8; NONCE_SIZE];
        
        let mut encrypted = vec![0u8; data.len() + TAG_SIZE];
        let mut encrypted_len = 0usize;
        
        let result = unsafe {
            encrypt_data(
                data.as_ptr(),
                data.len(),
                password.as_ptr(),
                password.len(),
                nonce.as_ptr(),
                encrypted.as_mut_ptr(),
                &mut encrypted_len as *mut usize,
            )
        };
        
        assert_eq!(result, 0);
        encrypted.truncate(encrypted_len);
        
        let mut decrypted = vec![0u8; encrypted_len];
        let mut decrypted_len = 0usize;
        
        let result = unsafe {
            decrypt_data(
                encrypted.as_ptr(),
                encrypted.len(),
                password.as_ptr(),
                password.len(),
                nonce.as_ptr(),
                decrypted.as_mut_ptr(),
                &mut decrypted_len as *mut usize,
            )
        };
        
        assert_eq!(result, 0);
        decrypted.truncate(decrypted_len);
        assert_eq!(decrypted, data);
    }
}