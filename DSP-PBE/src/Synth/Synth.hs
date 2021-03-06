{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

module Synth.Synth where

import Synth.SGD
import Synth.RTypeFilterGuess
import Synth.StructuralRefinement

import Analysis.FilterDistance

import Types.Common
import Types.Filter
import Types.DSPNode
import Types.SCCode

import qualified Settings as S
import Utils
import Control.Monad

import qualified Codec.Wav as W
import qualified Data.HashMap.Strict as H
import qualified Data.Map as M
import System.Random
import System.FilePath

-- | The main runner for DSP-PBE
--   this is a wrapper that handles the file io for runSynth
synthCode :: S.Options -> IO (Filter, Double, Int)
synthCode settings@S.SynthesisOptions{..} = do
  S.checkOptions settings
  fileActions <- mapM W.importFile [inputExample,outputExample] :: IO [Either String (AudioFormat)]
  (solutionProgram, score, structureAttempts) <- case sequence fileActions of
    Right fs -> do
       runSynth
           settings
           (head fs)
           (head $ tail fs)
    Left e -> error e
  debugPrint $ toSCCode solutionProgram
  if targetAudioPath /= ""
  then runFilter resultantAudioPath targetAudioPath (toVivid solutionProgram) 10 >> return ()
  else runFilter ("final/"++(takeBaseName outputExample)++"-synth.wav") inputExample (toVivid solutionProgram) 10 >> return ()
  return (solutionProgram, score, structureAttempts)

-- | Kicks off synthesis by using the user-provided refinements to select an initFilter
--   then enters the synthesis loop  
runSynth :: S.Options -> AudioFormat -> AudioFormat -> IO (Filter, Double, Int)
runSynth settings@S.SynthesisOptions{..} in_audio out_audio = do
  initFilter <- guessInitFilter (inputExample,in_audio) (outputExample,out_audio)
  debugPrint "Starting with best filter as:"
  debugPrint $ show initFilter
  synthLoop settings out_audio M.empty initFilter

-- | If we scored below the user provided threshold, we are done
--   If not we dervive new constraints on synthesis and try again
synthLoop :: S.Options -> AudioFormat -> FilterLog -> Filter -> IO (Filter, Double, Int)
synthLoop settings@S.SynthesisOptions{..} out_audio prevFLog prevFilter = do
  debugPrint "Initiating strucutral synthesis..."
  initFilter <- if prevFLog == M.empty --special case to catch the first time through the loop
               then return $ prevFilter
               else structuralRefinement settings out_audio prevFLog
  debugPrint "Found a program structure:"
  debugPrint $ show initFilter
  debugPrint "Initiating metrical synthesis..."
  debugPrint $ show $ M.size prevFLog
  (synthedFilter, score, fLog) <- parameterTuning settings inputExample (outputExample,out_audio) initFilter
  debugPrint $ show $ M.size fLog
  --let newFLog = M.union fLog prevFLog
  let newFLog = M.insert synthedFilter score prevFLog
  if score < epsilon || 
     M.size newFLog > filterLogSizeTimeout || 
     abs (score - (snd $ findMinByVal (M.union (M.fromList [(synthedFilter,99999)]) prevFLog))) < converganceGoal
  then do
    debugPrint $ ("Finished synthesis with score: "++ (show $ snd $ findMinByVal newFLog))
    return (fst $ findMinByVal newFLog, snd $ findMinByVal newFLog, M.size newFLog)
  else do
    synthLoop settings out_audio newFLog synthedFilter

-- | This uses stochastic gradient descent to find a minimal cost theta
--   SGD is problematic since we cannot analytically calculate a derivative of the cost function as the cost function is in IO
--   TODO Another option might be to use http://www.jhuapl.edu/SPSA/ which does not require the derivative
--   TODO many options here https://www.reddit.com/r/MachineLearning/comments/2e8797/gradient_descent_without_a_derivative/
parameterTuning :: S.Options -> FilePath -> (FilePath, AudioFormat) -> Filter -> IO (Filter, Double, FilterLog)
parameterTuning settings in_audio_fp (out_fp, out_audio) initF = do
  let costFxn = testFilter in_audio_fp (out_fp, out_audio)
  let rGen = mkStdGen 0
  debugPrint $ show initF
  initCost <- costFxn initF
  solution <- multiVarSGD settings costFxn rGen (M.singleton initF initCost) (extractThetaUpdaters initF) initF
  return solution

