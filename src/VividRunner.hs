{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE FlexibleContexts #-}

module VividRunner where
-- Courtesy of Murphy :)

import Vivid

runFilter :: FilePath -> FilePath -> (SDBody' '[] Signal -> SDBody' '[] Signal) -> IO(String)
runFilter out_filepath srcFile vCode = do
   writeNRT out_filepath $ vAction srcFile vCode
   return out_filepath


vAction :: FilePath -> (SDBody' '[] Signal -> SDBody' '[] Signal) -> _
vAction srcFile vCode = do
   b <- newBufferFromFile srcFile

   play $ do
     -- The "::Float"s are not necessary but I'm in a rush (and works across GHC versions):
     --playBuf (buf_ b, loop_ (0::Float), doneAction_ (2::Float))
     s0 <- playBuf (buf_ b, loop_ (0::Float), doneAction_ (2::Float))
     vCode $ toSig s0

   -- This is janky and there's a solution:
   wait 1.0 -- length in secs of the sample


