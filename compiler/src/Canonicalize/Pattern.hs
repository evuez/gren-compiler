{-# OPTIONS_GHC -Wall #-}

module Canonicalize.Pattern
  ( verify,
    Bindings,
    DupsDict,
    canonicalize,
  )
where

import AST.Canonical qualified as Can
import AST.Source qualified as Src
import Canonicalize.Environment qualified as Env
import Canonicalize.Environment.Dups qualified as Dups
import Data.Index qualified as Index
import Data.Map.Strict qualified as Map
import Data.Name qualified as Name
import Gren.ModuleName qualified as ModuleName
import Reporting.Annotation qualified as A
import Reporting.Error.Canonicalize qualified as Error
import Reporting.Result qualified as Result

-- RESULTS

type Result i w a =
  Result.Result i w Error.Error a

type Bindings =
  Map.Map Name.Name A.Region

-- VERIFY

verify :: Error.DuplicatePatternContext -> Result DupsDict w a -> Result i w (a, Bindings)
verify context (Result.Result k) =
  Result.Result $ \info warnings bad good ->
    k
      Dups.none
      warnings
      ( \_ warnings1 errors ->
          bad info warnings1 errors
      )
      ( \bindings warnings1 value ->
          case Dups.detect (Error.DuplicatePattern context) bindings of
            Result.Result k1 ->
              k1
                ()
                ()
                (\() () errs -> bad info warnings1 errs)
                (\() () dict -> good info warnings1 (value, dict))
      )

-- CANONICALIZE

type DupsDict =
  Dups.Dict A.Region

canonicalize :: Env.Env -> Src.Pattern -> Result DupsDict w Can.Pattern
canonicalize env (A.At region pattern) =
  A.At region
    <$> case pattern of
      Src.PAnything ->
        Result.ok Can.PAnything
      Src.PVar name ->
        logVar name region (Can.PVar name)
      Src.PRecord fields ->
        Can.PRecord <$> canonicalizeRecordFields env fields
      Src.PCtor nameRegion name patterns ->
        canonicalizeCtor env region name patterns =<< Env.findCtor nameRegion env name
      Src.PCtorQual nameRegion home name patterns ->
        canonicalizeCtor env region name patterns =<< Env.findCtorQual nameRegion env home name
      Src.PArray patterns ->
        Can.PArray <$> canonicalizeList env patterns
      Src.PAlias ptrn (A.At reg name) ->
        do
          cpattern <- canonicalize env ptrn
          logVar name reg (Can.PAlias cpattern name)
      Src.PChr chr ->
        Result.ok (Can.PChr chr)
      Src.PStr str ->
        Result.ok (Can.PStr str)
      Src.PInt int ->
        Result.ok (Can.PInt int)

canonicalizeRecordFields :: Env.Env -> [Src.RecordFieldPattern] -> Result DupsDict w [Can.PatternRecordField]
canonicalizeRecordFields env patterns =
  case patterns of
    [] ->
      Result.ok []
    pattern : otherPatterns ->
      (:)
        <$> canonicalizeRecordField env pattern
        <*> canonicalizeRecordFields env otherPatterns

canonicalizeRecordField :: Env.Env -> Src.RecordFieldPattern -> Result DupsDict w Can.PatternRecordField
canonicalizeRecordField env (A.At region (Src.RFPattern locatedName pattern)) =
  A.At region . Can.PRFieldPattern (A.toValue locatedName)
    <$> canonicalize env pattern

canonicalizeCtor :: Env.Env -> A.Region -> Name.Name -> [Src.Pattern] -> Env.Ctor -> Result DupsDict w Can.Pattern_
canonicalizeCtor env region name patterns ctor =
  case ctor of
    Env.Ctor home tipe union index args ->
      let toCanonicalArg argIndex argPattern argTipe =
            Can.PatternCtorArg argIndex argTipe <$> canonicalize env argPattern
       in do
            verifiedList <- Index.indexedZipWithA toCanonicalArg patterns args
            case verifiedList of
              Index.LengthMatch cargs ->
                if tipe == Name.bool && home == ModuleName.basics
                  then Result.ok (Can.PBool union (name == Name.true))
                  else Result.ok (Can.PCtor home tipe union name index cargs)
              Index.LengthMismatch actualLength expectedLength ->
                Result.throw (Error.BadArity region Error.PatternArity name expectedLength actualLength)

canonicalizeList :: Env.Env -> [Src.Pattern] -> Result DupsDict w [Can.Pattern]
canonicalizeList env list =
  case list of
    [] ->
      Result.ok []
    pattern : otherPatterns ->
      (:)
        <$> canonicalize env pattern
        <*> canonicalizeList env otherPatterns

-- LOG BINDINGS

logVar :: Name.Name -> A.Region -> a -> Result DupsDict w a
logVar name region value =
  Result.Result $ \bindings warnings _ ok ->
    ok (Dups.insert name region region bindings) warnings value
