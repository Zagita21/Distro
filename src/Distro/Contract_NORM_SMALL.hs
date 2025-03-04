
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}

module Distro.Contract
    (   distroValidator
    )   where

import           Plutus.V1.Ledger.Address  (Address, toPubKeyHash)
import           Plutus.V1.Ledger.Crypto   (PubKeyHash)
import           Plutus.V1.Ledger.Interval (contains, from)
import           Plutus.V1.Ledger.Scripts  (Datum (..), Redeemer (..))
import           Plutus.V1.Ledger.Value    (AssetClass (..), CurrencySymbol,
                                            assetClassValueOf, flattenValue)
import           Plutus.V2.Ledger.Contexts (ScriptContext (..),
                                            ScriptPurpose (..),
                                            TxInInfo (txInInfoResolved),
                                            TxInfo (..),
                                            TxOut (txOutDatum, txOutValue),
                                            findOwnInput, getContinuingOutputs,
                                            txSignedBy)
import           Plutus.V2.Ledger.Tx       (OutputDatum (..))
import           PlutusTx                  (BuiltinData, unsafeFromBuiltinData)
import qualified PlutusTx.AssocMap         as Map
import           PlutusTx.Prelude          (Bool (False, True), Integer,
                                            Maybe (Just, Nothing), all, error,
                                            length, not, otherwise, traceError,
                                            traceIfFalse, ($), (&&), (+), (==))

import           Distro.DataTypes          (DistroAction (..), DistroDatum (..),
                                            DistroParams (..),
                                            PhaseOneInfo (..),
                                            PhaseTwoInfo (..))
import           Regulator.DataTypes       (RegulatorAction (..))


{-==============================================================================================================================-}
{-==========                                            VALIDATOR SECTION                                             ==========-}
{-==============================================================================================================================-}

{-# INLINABLE distroValidator #-}
distroValidator :: DistroParams -> BuiltinData -> BuiltinData -> BuiltinData -> ()
distroValidator DistroParams{..} rawDatum rawRedeemer rawCTX =

    if case (redeemer , datum) of

        -----------------------------------------------------------------------------------------
        -- |                        PHASE ONE CLAIMING HAPPY TOKEN                            |--
        -----------------------------------------------------------------------------------------
        (PhaseOneClaimingToken mintingContractCS
            , DistroDatum happyToken PhaseOneInfo{..} phaseTwoInfo ) -> case getTxOutInlineDatum singleScriptOutputUTxO of
                Nothing           ->    traceIfFalse "The Output UTxO Does Not Have Inline DatumKKKKKKKKKKKKKKKK" False
                Just outputDatum  ->    case outputDatum of
                    (DistroDatum
                        happyToken'
                        (PhaseOneInfo
                            firstDevPhaseOneClaimAmount'
                            firstDevDidPhaseOne'
                            secondDevPhaseOneClaimAmount'
                            secondDevDidPhaseOne'
                            dateOfPhaseOne')
                        phaseTwoInfo') ->  case getMintingRedeemer mintingContractCS of

                            -----------------------------------------------------------------------------------------
                            -- |                       FIRST DEVELOPER CLAIMS AT PHASE ONE                        |--
                            -----------------------------------------------------------------------------------------
                            FirstDeveloperAction ->
                                do {
                                    let
                                                    {-|--------------------------------Minting Handling----------------------------------|-}
                                        mh1 = traceIfFalse "Wrong Minting Contract Currency Symbol/Policy ID"   $ currencySymbolOf happyToken == mintingContractCS
                                        mh2 = traceIfFalse "Wrong Amount Minted By First Developer"             $ assetClassValueOf txInfoMint happyToken == firstDevPhaseOneClaimAmount
                                        mh3 = traceIfFalse "Only 1 Token Burn/Mint Action Is Allowed"           $ length (flattenValue txInfoMint) == 1

                                                    {-|---------------------------------Time Handling------------------------------------|-}
                                        th1 = traceIfFalse "Phase One Date Has Not Been Reached"                $ from dateOfPhaseOne `contains` txInfoValidRange

                                                    {-|---------------------------------Datum Handling-----------------------------------|-}
                                        dh1 = traceIfFalse "Phase One Tokens Were Minted By First Dev"          $ not firstDevDidPhaseOne

                                        dh2 = traceIfFalse "happyToken Mismatch"                                $ happyToken == happyToken'

                                        dh3 = traceIfFalse "firstDevPhaseOneClaimAmount Mismatched"             $ firstDevPhaseOneClaimAmount  ==  firstDevPhaseOneClaimAmount'
                                        dh4 = traceIfFalse "firstDevDidPhaseOne Mismatched"                     $ not firstDevDidPhaseOne      ==  firstDevDidPhaseOne'
                                        dh5 = traceIfFalse "secondDevPhaseOneClaimAmount Mismatched"            $ secondDevPhaseOneClaimAmount ==  secondDevPhaseOneClaimAmount'
                                        dh6 = traceIfFalse "secondDevDidPhaseOne Mismatched"                    $ secondDevDidPhaseOne         ==  secondDevDidPhaseOne'
                                        dh7 = traceIfFalse "dateOfPhaseOne Mismatched"                          $ dateOfPhaseOne               ==  dateOfPhaseOne'

                                        dh8 = traceIfFalse "phaseTwoInfo Mismatched"                            $ phaseTwoInfo == phaseTwoInfo'

                                                    {-|----------------------------------Input/Output------------------------------------|-}
                                        io1 = traceIfFalse "SC Output UTxO Has No Happy State Token"            $ assetClassValueOf (txOutValue singleScriptOutputUTxO) happyToken == 1
                                        io2 = traceIfFalse "SC Input UTxO Has No Happy State Token"             $ assetClassValueOf (txOutValue singleScriptInputUTxO) happyToken == 1
                                        io3 = traceIfFalse "Script Input & Output Must Be Equal"                $ txOutValue singleScriptInputUTxO == txOutValue singleScriptOutputUTxO

                                    in
                                        traceIfFalse "[ERROR]: FIRST DEVELOPER CLAIMS AT PHASE ONE"             $ all ( == ( True :: Bool ) ) [mh1,mh2,mh3,th1,dh1,dh2,dh3,dh4,dh5,dh6,dh7,dh8,io1,io2,io3]
                                    }

                            -----------------------------------------------------------------------------------------
                            -- |                       SECOND DEVELOPER CLAIMS AT PHASE ONE                       |--
                            -----------------------------------------------------------------------------------------
                            SecondDeveloperAction ->
                                do {
                                    let
                                                    {-|--------------------------------Minting Handling----------------------------------|-}
                                        mh1 = traceIfFalse "Wrong Minting Contract Currency Symbol/Policy ID"   $ currencySymbolOf happyToken == mintingContractCS
                                        mh2 = traceIfFalse "Wrong Amount Minted By Second Developer"            $ assetClassValueOf txInfoMint happyToken == secondDevPhaseOneClaimAmount
                                        mh3 = traceIfFalse "Only 1 Token Burn/Mint Action Is Allowed"           $ length (flattenValue txInfoMint) == 1

                                                    {-|---------------------------------Time Handling------------------------------------|-}
                                        th1 = traceIfFalse "Phase One Date Has Not Been Reached"                $ from dateOfPhaseOne `contains` txInfoValidRange

                                                    {-|---------------------------------Datum Handling-----------------------------------|-}
                                        dh1 = traceIfFalse "Phase One Tokens Were Minted By Second Dev"         $ not secondDevDidPhaseOne

                                        dh2 = traceIfFalse "happyToken Mismatch"                                $ happyToken == happyToken'

                                        dh3 = traceIfFalse "firstDevPhaseOneClaimAmount Mismatched"             $ firstDevPhaseOneClaimAmount  ==  firstDevPhaseOneClaimAmount'
                                        dh4 = traceIfFalse "firstDevDidPhaseOne Mismatched"                     $ firstDevDidPhaseOne          ==  firstDevDidPhaseOne'
                                        dh5 = traceIfFalse "secondDevPhaseOneClaimAmount Mismatched"            $ secondDevPhaseOneClaimAmount ==  secondDevPhaseOneClaimAmount'
                                        dh6 = traceIfFalse "secondDevDidPhaseOne Mismatched"                    $ not secondDevDidPhaseOne     ==  secondDevDidPhaseOne'
                                        dh7 = traceIfFalse "dateOfPhaseOne Mismatched"                          $ dateOfPhaseOne               ==  dateOfPhaseOne'

                                        dh8 = traceIfFalse "phaseTwoInfo Mismatched"                            $ phaseTwoInfo == phaseTwoInfo'

                                                    {-|----------------------------------Input/Output------------------------------------|-}
                                        io1 = traceIfFalse "SC Output UTxO Has No Happy State Token"            $ assetClassValueOf (txOutValue singleScriptOutputUTxO) happyToken == 1
                                        io2 = traceIfFalse "SC Input UTxO Has No Happy State Token"             $ assetClassValueOf (txOutValue singleScriptInputUTxO) happyToken == 1
                                        io3 = traceIfFalse "Script Input & Output Must Be Equal"                $ txOutValue singleScriptInputUTxO == txOutValue singleScriptOutputUTxO

                                    in
                                        traceIfFalse "[ERROR]: SECOND DEVELOPER CLAIMS AT PHASE ONE"            $ all ( == ( True :: Bool ) ) [mh1,mh2,mh3,th1,dh1,dh2,dh3,dh4,dh5,dh6,dh7,dh8,io1,io2,io3]
                                    }

                            _ -> error()

        -----------------------------------------------------------------------------------------
        -- |                         PHASE TWO CLAIMING HAPPY TOKEN                           |--
        -----------------------------------------------------------------------------------------
        (PhaseTwoClaimingToken mintingContractCS
            , DistroDatum happyToken PhaseOneInfo{..} PhaseTwoInfo{..} ) -> case getTxOutInlineDatum singleScriptOutputUTxO of
                Nothing           ->    traceIfFalse "The Output UTxO Does Not Have Inline Datum" False
                Just outputDatum  ->    case outputDatum of
                    (DistroDatum
                        happyToken'
                        (PhaseOneInfo
                            firstDevPhaseOneClaimAmount'
                            firstDevDidPhaseOne'
                            secondDevPhaseOneClaimAmount'
                            secondDevDidPhaseOne'
                            dateOfPhaseOne')
                        (PhaseTwoInfo
                            firstDevPhaseTwoClaimAmount'
                            firstDevDidPhaseTwo'
                            secondDevPhaseTwoClaimAmount'
                            secondDevDidPhaseTwo'
                            dateOfPhaseTwo')) ->  case getMintingRedeemer mintingContractCS of

                            -----------------------------------------------------------------------------------------
                            -- |                       FIRST DEVELOPER CLAIMS AT PHASE TWO                        |--
                            -----------------------------------------------------------------------------------------
                            FirstDeveloperAction ->
                                do {
                                    let
                                                    {-|--------------------------------Minting Handling----------------------------------|-}
                                        mh1 = traceIfFalse "Wrong Minting Contract Currency Symbol/Policy ID"   $ currencySymbolOf happyToken == mintingContractCS
                                        mh2 = traceIfFalse "Wrong Amount Minted By First Developer"             $ if firstDevDidPhaseOne
                                                                                                                    then assetClassValueOf txInfoMint happyToken == firstDevPhaseTwoClaimAmount
                                                                                                                    else assetClassValueOf txInfoMint happyToken == firstDevPhaseTwoClaimAmount + firstDevPhaseOneClaimAmount
                                        mh3 = traceIfFalse "Only 1 Token Burn/Mint Action Is Allowed"           $ length (flattenValue txInfoMint) == 1

                                                    {-|---------------------------------Time Handling------------------------------------|-}
                                        th1 = traceIfFalse "Phase Two Date Has Not Been Reached"                $ from dateOfPhaseTwo `contains` txInfoValidRange

                                                    {-|---------------------------------Datum Handling-----------------------------------|-}
                                        dh1 = traceIfFalse "Phase Two Tokens Were Minted By First Dev"          $ not firstDevDidPhaseTwo

                                        dh2 = traceIfFalse "happyToken Mismatch"                                $ happyToken == happyToken'

                                        dh3 = traceIfFalse "firstDevPhaseOneClaimAmount Mismatched"             $ firstDevPhaseOneClaimAmount  ==  firstDevPhaseOneClaimAmount'
                                        dh4 = traceIfFalse "firstDevDidPhaseOne Mismatched"                     $ if firstDevDidPhaseOne
                                                                                                                    then firstDevDidPhaseOne        ==  firstDevDidPhaseOne'
                                                                                                                    else not firstDevDidPhaseOne    ==  firstDevDidPhaseOne'
                                        dh5 = traceIfFalse "secondDevPhaseOneClaimAmount Mismatched"            $ secondDevPhaseOneClaimAmount ==  secondDevPhaseOneClaimAmount'
                                        dh6 = traceIfFalse "secondDevDidPhaseOne Mismatched"                    $ secondDevDidPhaseOne         ==  secondDevDidPhaseOne'
                                        dh7 = traceIfFalse "dateOfPhaseOne Mismatched"                          $ dateOfPhaseOne               ==  dateOfPhaseOne'

                                        dh8 = traceIfFalse "firstDevPhaseTwoClaimAmount Mismatched"             $ firstDevPhaseTwoClaimAmount  ==  firstDevPhaseTwoClaimAmount'
                                        dh9 = traceIfFalse "firstDevDidPhaseTwo Mismatched"                     $ not firstDevDidPhaseTwo      ==  firstDevDidPhaseTwo'
                                        dh10 = traceIfFalse "secondDevPhaseTwoClaimAmount Mismatched"           $ secondDevPhaseTwoClaimAmount ==  secondDevPhaseTwoClaimAmount'
                                        dh11 = traceIfFalse "secondDevDidPhaseTwo Mismatched"                   $ secondDevDidPhaseTwo         ==  secondDevDidPhaseTwo'
                                        dh12 = traceIfFalse "dateOfPhaseTwo Mismatched"                         $ dateOfPhaseTwo               ==  dateOfPhaseTwo'

                                                    {-|----------------------------------Input/Output------------------------------------|-}
                                        io1 = traceIfFalse "SC Output UTxO Has No Happy State Token"            $ assetClassValueOf (txOutValue singleScriptOutputUTxO) happyToken == 1
                                        io2 = traceIfFalse "SC Input UTxO Has No Happy State Token"             $ assetClassValueOf (txOutValue singleScriptInputUTxO) happyToken == 1
                                        io3 = traceIfFalse "Script Input & Output Must Be Equal"                $ txOutValue singleScriptInputUTxO == txOutValue singleScriptOutputUTxO
                                    in
                                        traceIfFalse "[ERROR]: FIRST DEVELOPER CLAIMS AT PHASE TWO"             $ all ( == ( True :: Bool ) ) [mh1,mh2,mh3,th1,dh1,dh2,dh3,dh4,dh5,dh6,dh7,dh8,dh9,dh10,dh11,dh12,io1,io2,io3]
                                    }

                            -----------------------------------------------------------------------------------------
                            -- |                       SECOND DEVELOPER CLAIMS AT PHASE TWO                       |--
                            -----------------------------------------------------------------------------------------
                            SecondDeveloperAction ->
                                do {
                                    let
                                                    {-|--------------------------------Minting Handling----------------------------------|-}
                                        mh1 = traceIfFalse "Wrong Minting Contract Currency Symbol/Policy ID"   $ currencySymbolOf happyToken == mintingContractCS
                                        mh2 = traceIfFalse "Wrong Amount Minted By Second Developer"            $ if secondDevDidPhaseOne
                                                                                                                    then assetClassValueOf txInfoMint happyToken == secondDevPhaseTwoClaimAmount
                                                                                                                    else assetClassValueOf txInfoMint happyToken == secondDevPhaseTwoClaimAmount + secondDevPhaseOneClaimAmount
                                        mh3 = traceIfFalse "Only 1 Token Burn/Mint Action Is Allowed"           $ length (flattenValue txInfoMint) == 1

                                                    {-|---------------------------------Time Handling------------------------------------|-}
                                        th1 = traceIfFalse "Phase Two Date Has Not Been Reached"                $ from dateOfPhaseTwo `contains` txInfoValidRange

                                                    {-|---------------------------------Datum Handling-----------------------------------|-}
                                        dh1 = traceIfFalse "Phase Two Tokens Were Minted By Second Dev"         $ not secondDevDidPhaseTwo

                                        dh2 = traceIfFalse "happyToken Mismatch"                                $ happyToken == happyToken'

                                        dh3 = traceIfFalse "firstDevPhaseOneClaimAmount Mismatched"             $ firstDevPhaseOneClaimAmount   ==  firstDevPhaseOneClaimAmount'
                                        dh4 = traceIfFalse "firstDevDidPhaseOne Mismatched"                     $ firstDevDidPhaseOne           ==  firstDevDidPhaseOne'
                                        dh5 = traceIfFalse "secondDevPhaseOneClaimAmount Mismatched"            $ secondDevPhaseOneClaimAmount  ==  secondDevPhaseOneClaimAmount'
                                        dh6 = traceIfFalse "secondDevDidPhaseOne Mismatched"                    $ if secondDevDidPhaseOne
                                                                                                                    then secondDevDidPhaseOne       ==  secondDevDidPhaseOne'
                                                                                                                    else not secondDevDidPhaseOne   ==  secondDevDidPhaseOne'
                                        dh7 = traceIfFalse "dateOfPhaseOne Mismatched"                          $ dateOfPhaseOne                ==  dateOfPhaseOne'

                                        dh8 = traceIfFalse "firstDevPhaseTwoClaimAmount Mismatched"             $ firstDevPhaseTwoClaimAmount   ==  firstDevPhaseTwoClaimAmount'
                                        dh9 = traceIfFalse "firstDevDidPhaseTwo Mismatched"                     $ firstDevDidPhaseTwo           ==  firstDevDidPhaseTwo'
                                        dh10 = traceIfFalse "secondDevPhaseTwoClaimAmount Mismatched"           $ secondDevPhaseTwoClaimAmount  ==  secondDevPhaseTwoClaimAmount'
                                        dh11 = traceIfFalse "secondDevDidPhaseTwo Mismatched"                   $ not secondDevDidPhaseTwo      ==  secondDevDidPhaseTwo'
                                        dh12 = traceIfFalse "dateOfPhaseTwo Mismatched"                         $ dateOfPhaseTwo                ==  dateOfPhaseTwo'

                                                    {-|----------------------------------Input/Output------------------------------------|-}
                                        io1 = traceIfFalse "SC Output UTxO Has No Happy State Token"            $ assetClassValueOf (txOutValue singleScriptOutputUTxO) happyToken == 1
                                        io2 = traceIfFalse "SC Input UTxO Has No Happy State Token"             $ assetClassValueOf (txOutValue singleScriptInputUTxO) happyToken == 1
                                        io3 = traceIfFalse "Script Input & Output Must Be Equal"                $ txOutValue singleScriptInputUTxO == txOutValue singleScriptOutputUTxO

                                    in
                                        traceIfFalse "[ERROR]: SECOND DEVELOPER CLAIMS AT PHASE TWO"            $ all ( == ( True :: Bool ) ) [mh1,mh2,mh3,th1,dh1,dh2,dh3,dh4,dh5,dh6,dh7,dh8,dh9,dh10,dh11,dh12,io1,io2,io3]
                                    }

                            _ -> error ()

        -----------------------------------------------------------------------------------------
        -- |                              BURNING GENESIS TOKEN                               |--
        -----------------------------------------------------------------------------------------
        (BurningGenesisToken mintingContractCS
            , DistroDatum happyToken PhaseOneInfo{..} PhaseTwoInfo{..} ) -> case getMintingRedeemer mintingContractCS of

                -----------------------------------------------------------------------------------------
                -- |                        FIRST DEVELOPER BURN GENESIS TOKEN                        |--
                -----------------------------------------------------------------------------------------
                FirstDeveloperAction ->
                    do {
                        let
                                        {-|--------------------------------Minting Handling----------------------------------|-}
                            mh1 = traceIfFalse "Wrong Minting Contract Currency Symbol/Policy ID"   $ currencySymbolOf happyToken == mintingContractCS
                            mh2 = traceIfFalse "Wrong Amount Minted By First Developer"             $ assetClassValueOf txInfoMint happyToken == -1
                            mh3 = traceIfFalse "Only 1 Token Burn/Mint Action Is Allowed"           $ length (flattenValue txInfoMint) == 1

                                        {-|---------------------------------Datum Handling-----------------------------------|-}
                            dh1 = traceIfFalse "One Or More Dev Has Not Claim Their Token"          $       firstDevDidPhaseOne
                                                                                                        &&  secondDevDidPhaseOne
                                                                                                        &&  firstDevDidPhaseTwo
                                                                                                        &&  secondDevDidPhaseTwo

                                        {-|----------------------------------Input/Output------------------------------------|-}
                            io1 = traceIfFalse "SC Output UTxO Has No Happy State Token"            $ assetClassValueOf (txOutValue singleScriptOutputUTxO) happyToken == 1

                        in
                            traceIfFalse "[ERROR]: FIRST DEVELOPER BURN GENESIS TOKEN"              $ all ( == ( True :: Bool ) ) [mh1,mh2,mh3,dh1,io1]
                        }

                -----------------------------------------------------------------------------------------
                -- |                        SECOND DEVELOPER BURN GENESIS TOKEN                       |--
                -----------------------------------------------------------------------------------------
                SecondDeveloperAction ->
                    do {
                        let
                                        {-|--------------------------------Minting Handling----------------------------------|-}
                            mh1 = traceIfFalse "Wrong Minting Contract Currency Symbol/Policy ID"   $ currencySymbolOf happyToken == mintingContractCS
                            mh2 = traceIfFalse "Wrong Amount Minted By Second Developer"            $ assetClassValueOf txInfoMint happyToken == -1
                            mh3 = traceIfFalse "Only 1 Token Burn/Mint Action Is Allowed"           $ length (flattenValue txInfoMint) == 1

                                        {-|---------------------------------Datum Handling-----------------------------------|-}
                            dh1 = traceIfFalse "One Or More Dev Has Not Claim Their Token"          $       firstDevDidPhaseOne
                                                                                                        &&  secondDevDidPhaseOne
                                                                                                        &&  firstDevDidPhaseTwo
                                                                                                        &&  secondDevDidPhaseTwo

                                        {-|----------------------------------Input/Output------------------------------------|-}
                            io1 = traceIfFalse "SC Output UTxO Has No Happy State Token"            $ assetClassValueOf (txOutValue singleScriptOutputUTxO) happyToken == 1

                        in
                            traceIfFalse "[ERROR]: SECOND DEVELOPER BURN GENESIS TOKEN"             $ all ( == ( True :: Bool ) ) [mh1,mh2,mh3,dh1,io1]
                        }

                _ -> error ()

        -----------------------------------------------------------------------------------------
        -- |                             DISTRO DEBUGGER ACTION                               |--
        -----------------------------------------------------------------------------------------

        ( DistroDebuggerAction
            , DistroDatum {}
            ) ->
                traceIfFalse "Distro Debugger Must Sign"  $ txSignedBy ctxTxInfo distroDebuggerPKH

    then    ()  else    error()

        where

            datum :: DistroDatum
            datum = unsafeFromBuiltinData @DistroDatum rawDatum

            redeemer :: DistroAction
            redeemer = unsafeFromBuiltinData @DistroAction rawRedeemer

            ctx :: ScriptContext
            ctx@ScriptContext{ scriptContextTxInfo = TxInfo{..} }  = unsafeFromBuiltinData @ScriptContext rawCTX

            ctxTxInfo :: TxInfo
            ctxTxInfo = scriptContextTxInfo ctx

            getMintingRedeemer :: CurrencySymbol -> RegulatorAction
            getMintingRedeemer cs
                |   Just rawMintingRedeemer <- Map.lookup (Minting cs) txInfoRedeemers
                =   unsafeFromBuiltinData @RegulatorAction $ getRedeemer rawMintingRedeemer
                |   otherwise   = traceError "No Redeemer Found"


            currencySymbolOf :: AssetClass -> CurrencySymbol
            currencySymbolOf (AssetClass (cs, _)) = cs

            singleScriptOutputUTxO :: TxOut
            singleScriptOutputUTxO
                |   [o]         <-  getContinuingOutputs ctx = o
                |   otherwise   =   traceError "No Script Output"

            singleScriptInputUTxO :: TxOut
            singleScriptInputUTxO
                |   Just i      <-  findOwnInput ctx = txInInfoResolved i
                |   otherwise   =   traceError "No Script Input"

            getTxOutInlineDatum :: TxOut -> Maybe DistroDatum
            getTxOutInlineDatum tx
                | ( OutputDatum ( Datum inline )) <- txOutDatum tx
                = Just $ unsafeFromBuiltinData @DistroDatum inline
                | otherwise = Nothing


{-================================================== END OF VALIDATOR SECTION ====================================================-}
