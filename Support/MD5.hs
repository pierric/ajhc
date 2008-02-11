{-# OPTIONS -funbox-strict-fields  -O2 #-}
module Support.MD5(Hash(),emptyHash,md5,md5file,md5Bytes,md5String,md5Handle,hashToBytes) where

import qualified Data.ByteString as BS
import Data.Binary
import Control.Monad
import qualified Data.ByteString.Unsafe as BS
import Foreign
import Foreign.C
import Data.Bits
import Data.Word
import Data.Char
import System.IO


data Hash = Hash !Word32 !Word32 !Word32 !Word32
    deriving(Eq,Ord)


md5 :: BS.ByteString -> Hash
md5 bs = unsafePerformIO $ allocaBytes 16 $ \digest -> do
        BS.unsafeUseAsCStringLen bs $ \ (x,y) -> md5Data (castPtr x) (fromIntegral y) digest
        readDigest digest

readDigest digest = do
    w1 <- peekWord32 digest 0
    w2 <- peekWord32 digest 4
    w3 <- peekWord32 digest 8
    w4 <- peekWord32 digest 12
    return $ Hash w1 w2 w3 w4

peekWord32 ptr off = do
    b1 <- peekByteOff ptr off       :: IO Word8
    b2 <- peekByteOff ptr (off + 1) :: IO Word8
    b3 <- peekByteOff ptr (off + 2) :: IO Word8
    b4 <- peekByteOff ptr (off + 3) :: IO Word8
    let fi = fromIntegral :: Word8 -> Word32
    return (fi b1 `shiftL` 24 .|. fi b2 `shiftL` 16 .|. fi b3 `shiftL` 8 .|. fi b4)

instance Binary Hash where
    put (Hash a b c d) = put a >> put b >> put c >> put d
    get = return Hash `ap` get `ap` get `ap` get `ap` get

md5file :: FilePath -> IO Hash
md5file fp = md5 `fmap` BS.readFile fp


foreign import ccall unsafe "md5_data" md5Data :: Ptr Word8 -> CInt -> Ptr Word8 -> IO ()

hashToBytes :: Hash -> [Word8]
hashToBytes (Hash a b c d) = tb a . tb b . tb c . tb d $ [] where
    tb :: Word32 -> [Word8] -> [Word8]
    tb n = showIt 4 n
    showIt :: Int -> Word32 -> [Word8] -> [Word8]
    showIt 0 _ r = r
    showIt i x r = case quotRem x 256 of
                       (y, z) -> let c = fromIntegral z
                                 in c `seq` showIt (i-1) y (c:r)


instance Show Hash where
    showsPrec _ (Hash a b c d) = showAsHex a . showAsHex b . showAsHex c . showAsHex d

showAsHex :: Word32 -> ShowS
showAsHex n = showIt 8 n
   where
    showIt :: Int -> Word32 -> String -> String
    showIt 0 _ r = r
    showIt i x r = case quotRem x 16 of
                       (y, z) -> let c = intToDigit (fromIntegral z)
                                 in c `seq` showIt (i-1) y (c:r)

emptyHash = Hash 0 0 0 0

md5Bytes :: [Word8] -> Hash
md5Bytes bs = unsafePerformIO $ allocaBytes 16 $ \digest -> do
        withArrayLen bs $ \y x -> md5Data (castPtr x) (fromIntegral y) digest
        readDigest digest

md5String :: String -> Hash
md5String ss = md5Bytes (toUTF ss) where
    -- | Convert Unicode characters to UTF-8.
    toUTF :: String -> [Word8]
    toUTF [] = []
    toUTF (x:xs) | ord x<=0x007F = (fromIntegral $ ord x):toUTF xs
                 | ord x<=0x07FF = fromIntegral (0xC0 .|. ((ord x `shift` (-6)) .&. 0x1F)):
                                   fromIntegral (0x80 .|. (ord x .&. 0x3F)):
                                   toUTF xs
                 | otherwise     = fromIntegral (0xE0 .|. ((ord x `shift` (-12)) .&. 0x0F)):
                                   fromIntegral (0x80 .|. ((ord x `shift` (-6)) .&. 0x3F)):
                                   fromIntegral (0x80 .|. (ord x .&. 0x3F)):
                                   toUTF xs

-- XXX inefficient, don't use it.
md5Handle :: Handle -> IO Hash
md5Handle h = do
    hSeek h AbsoluteSeek 0
    len <- fromIntegral `liftM` hFileSize h
    allocaBytes len $ \ptr -> do
    cnt <- hGetBuf h ptr len
    unless (cnt == len) $ fail "md5File - read returned too few bytes"
    hSeek h AbsoluteSeek 0
    allocaBytes 16 $ \digest -> do
        md5Data ptr (fromIntegral len) digest
        readDigest digest

