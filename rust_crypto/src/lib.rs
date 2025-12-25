use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use rayon::prelude::*;
use sha2::{Digest, Sha256};
use std::slice;
use std::sync::Arc;

const NONCE_SIZE: usize = 12;
const TAG_SIZE: usize = 16;

fn derive_key(password: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(password);
    let result = hasher.finalize();
    let mut key = [0u8; 32];
    key.copy_from_slice(&result);
    key
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