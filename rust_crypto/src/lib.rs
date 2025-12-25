use aes::Aes256;
use cbc::{Decryptor, Encryptor};
use cbc::cipher::{BlockDecryptMut, BlockEncryptMut, KeyIvInit};
use sha2::{Digest, Sha256};
use std::slice;

type Aes256CbcEnc = Encryptor<Aes256>;
type Aes256CbcDec = Decryptor<Aes256>;

const BLOCK_SIZE: usize = 16;

fn derive_key(password: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(password);
    let result = hasher.finalize();
    let mut key = [0u8; 32];
    key.copy_from_slice(&result);
    key
}

fn pkcs7_pad(data: &[u8]) -> Vec<u8> {
    let padding_len = BLOCK_SIZE - (data.len() % BLOCK_SIZE);
    let mut padded = Vec::with_capacity(data.len() + padding_len);
    padded.extend_from_slice(data);
    padded.extend(std::iter::repeat(padding_len as u8).take(padding_len));
    padded
}

fn pkcs7_unpad(data: &[u8]) -> Result<Vec<u8>, &'static str> {
    if data.is_empty() {
        return Err("Empty data");
    }
    
    let padding_len = data[data.len() - 1] as usize;
    
    if padding_len == 0 || padding_len > BLOCK_SIZE {
        return Err("Invalid padding");
    }
    
    if data.len() < padding_len {
        return Err("Invalid padding length");
    }
    
    for i in 0..padding_len {
        if data[data.len() - 1 - i] != padding_len as u8 {
            return Err("Invalid padding bytes");
        }
    }
    
    Ok(data[..data.len() - padding_len].to_vec())
}

#[no_mangle]
pub extern "C" fn encrypt_data(
    data_ptr: *const u8,
    data_len: usize,
    password_ptr: *const u8,
    password_len: usize,
    iv_ptr: *const u8,
    output_ptr: *mut u8,
    output_len: *mut usize,
) -> i32 {
    unsafe {
        let data = slice::from_raw_parts(data_ptr, data_len);
        let password = slice::from_raw_parts(password_ptr, password_len);
        let iv = slice::from_raw_parts(iv_ptr, 16);
        
        let key = derive_key(password);
        let padded_data = pkcs7_pad(data);
        
        let mut iv_array = [0u8; 16];
        iv_array.copy_from_slice(iv);
        
        let cipher = Aes256CbcEnc::new(&key.into(), &iv_array.into());
        let encrypted = cipher.encrypt_padded_vec_mut::<cbc::cipher::block_padding::NoPadding>(&padded_data);
        
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
    iv_ptr: *const u8,
    output_ptr: *mut u8,
    output_len: *mut usize,
) -> i32 {
    unsafe {
        let encrypted = slice::from_raw_parts(encrypted_ptr, encrypted_len);
        let password = slice::from_raw_parts(password_ptr, password_len);
        let iv = slice::from_raw_parts(iv_ptr, 16);
        
        let key = derive_key(password);
        
        let mut iv_array = [0u8; 16];
        iv_array.copy_from_slice(iv);
        
        let cipher = Aes256CbcDec::new(&key.into(), &iv_array.into());
        
        let decrypted = match cipher.decrypt_padded_vec_mut::<cbc::cipher::block_padding::NoPadding>(encrypted) {
            Ok(d) => d,
            Err(_) => return -1,
        };
        
        let unpadded = match pkcs7_unpad(&decrypted) {
            Ok(u) => u,
            Err(_) => return -2,
        };
        
        *output_len = unpadded.len();
        
        if !output_ptr.is_null() {
            std::ptr::copy_nonoverlapping(unpadded.as_ptr(), output_ptr, unpadded.len());
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
        let iv = [0u8; 16];
        
        let mut encrypted = vec![0u8; data.len() + 32];
        let mut encrypted_len = 0usize;
        
        let result = unsafe {
            encrypt_data(
                data.as_ptr(),
                data.len(),
                password.as_ptr(),
                password.len(),
                iv.as_ptr(),
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
                iv.as_ptr(),
                decrypted.as_mut_ptr(),
                &mut decrypted_len as *mut usize,
            )
        };
        
        assert_eq!(result, 0);
        decrypted.truncate(decrypted_len);
        assert_eq!(decrypted, data);
    }

    #[test]
    fn test_padding() {
        let data = b"12345678901234";
        let padded = pkcs7_pad(data);
        assert_eq!(padded.len() % BLOCK_SIZE, 0);
        
        let unpadded = pkcs7_unpad(&padded).unwrap();
        assert_eq!(unpadded, data);
    }
}