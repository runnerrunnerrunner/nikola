{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : Data.Array.Nikola.Language.Reify
-- Copyright   : (c) The President and Fellows of Harvard College 2009-2010
-- Copyright   : (c) Geoffrey Mainland 2012
-- License     : BSD-style
--
-- Maintainer  : Geoffrey Mainland <mainland@apeiron.net>
-- Stability   : experimental
-- Portability : non-portable

module Data.Array.Nikola.Language.Reify (
    Reifiable(..),

    vapply
  ) where

import Prelude hiding ((++), map, replicate, reverse)
import qualified Prelude as P

import Control.Applicative
import Data.Typeable (Typeable)
-- import Text.PrettyPrint.Mainland

import Data.Array.Nikola.Array
import Data.Array.Nikola.Exp
import Data.Array.Nikola.Repr.Delayed
import Data.Array.Nikola.Repr.Manifest
import Data.Array.Nikola.Shape

import Data.Array.Nikola.Language.Generic
import Data.Array.Nikola.Language.Monad
import Data.Array.Nikola.Language.Sharing
import qualified Data.Array.Nikola.Language.Syntax as S
import Data.Array.Nikola.Language.Syntax hiding (Exp, Var)
-- import Data.Array.Nikola.Pretty

-- | 'Reifiable a b' mean that an 'a' can be reified as a 'b'.
class Typeable a => Reifiable a b where
    reify :: a -> R b b

-- These are the base cases for procedure reification.
instance (IsElem (Exp t a)) => Reifiable (Exp t a) ProcH where
    reify e = liftK $ returnK e

instance Reifiable (P ()) ProcH where
    reify m = liftK $ m >> return (ReturnK UnitE)

instance (IsElem (Exp t a)) => Reifiable (P (Exp t a)) ProcH where
    reify m = liftK $ m >>= returnK

instance (Typeable r,
          Shape sh,
          IsElem a,
          Manifest r a)
      => Reifiable (Array r sh a) ProcH where
    reify arr = liftK $ do
        AManifest _ arr <- mkManifest arr
        returnK $ E arr

instance (Typeable r,
          Shape sh,
          IsElem a,
          Manifest r a)
      => Reifiable (P (Array r sh a)) ProcH where
    reify m = liftK $ do
        AManifest _ arr <- m >>= mkManifest
        returnK $ E arr

liftK :: P ProgK -> R ProcH ProcH
liftK m =
    lamH [] $ do
    ProcH [] <$> resetH m

returnK :: Exp t a -> P ProgK
returnK = return . ReturnK . unE

-- These are the inductive cases

instance (IsElem (Exp t a),
          Reifiable b ProcH)
    => Reifiable (Exp t a -> b) ProcH where
    reify f = do
        v <- gensym "x"
        lamH [(v, ScalarT tau)] $ do
        reify $ f (E (VarE v))
      where
        tau :: ScalarType
        tau = typeOf (undefined :: Exp t a)

instance (Shape sh,
          IsElem a,
          Reifiable b ProcH) => Reifiable (Array M sh a -> b) ProcH where
    reify f = do
        v        <- gensym "vec"
        let n    =  rank (undefined :: sh)
        let dims =  [DimE i n (VarE v) | i <- [0..n-1]]
        let sh   =  shapeOfList (P.map E dims)
        lamH [(v, ArrayT tau n)] $ do
        reify $ f (AManifest sh (VarE v))
      where
        tau :: ScalarType
        tau = typeOf (undefined :: a)

-- Base case

instance (IsElem (Exp t a)) => Reifiable (Exp t a) S.Exp where
    reify e = return $ unE e

-- Inductive case

instance (IsElem (Exp t a),
          Reifiable b S.Exp)
    => Reifiable (Exp t a -> b) S.Exp where
    reify f = do
        v <- gensym "x"
        lamE [(v, ScalarT tau)] $ do
        reify $ f (E (VarE v))
      where
        tau :: ScalarType
        tau = typeOf (undefined :: Exp t a)

-- | @vapply@ is a bit tricky... We first build a @DelayedE@ AST node containing
-- an action that reifies the lambda. Then we wrap the result in enough
-- (Haskell) lambdas and (Nikola) @AppE@ constructors to turn in back into a
-- Haskell function (at the original type) whose body is a Nikola application
-- term.
class (Reifiable a S.Exp) => VApply a where
    vapply :: a -> a
    vapply f = vapplyk (DelayedE (cacheExp f (reset (reify f >>= detectSharing ExpA)))) []

    vapplyk :: S.Exp -> [S.Exp] -> a

instance (IsElem (Exp t a),
          IsElem (Exp t b)) => VApply (Exp t a -> Exp t b) where
    vapplyk f es = \e -> E $ AppE f (P.reverse (unE e : es))

instance (IsElem (Exp t a),
          VApply (b -> c)) => VApply (Exp t a -> b -> c) where
    vapplyk f es = \e -> vapplyk f (unE e : es)
