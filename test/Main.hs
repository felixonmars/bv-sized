{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Main where

-- Testing modules
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.Hedgehog

-- Modules under test
import qualified Data.BitVector.Sized as BV

-- Auxiliary modules
import Data.Parameterized.NatRepr
import Data.Parameterized.Some

----------------------------------------
-- Utilities
forcePos :: (1 <= w => NatRepr w -> a)
         -> NatRepr w -> a
forcePos f w = case isZeroOrGT1 w of
  Left Refl -> error "Main.forcePos: encountered 0 nat"
  Right LeqProof -> f w

----------------------------------------
-- Homomorphisms
un :: Show a
   => Gen (Some NatRepr)
   -- ^ generator for width
   -> (forall w . NatRepr w -> a -> BV.BV w)
   -- ^ morphism
   -> (forall w . NatRepr w -> Gen a)
   -- ^ generator for arg
   -> (forall w . NatRepr w -> a -> a)
   -- ^ unary operator on domain
   -> (forall w . NatRepr w -> BV.BV w -> BV.BV w)
   -- ^ unary operator on codomain
   -> Property
un genW p gen aOp bOp = property $ do
  Some w <- forAll genW
  a <- forAll (gen w)

  p w (aOp w a) === bOp w (p w a)

bin :: Show a
    => Gen (Some NatRepr)
    -- ^ generator for width
    -> (forall w. NatRepr w -> a -> BV.BV w)
    -- ^ morphism on domains
    -> (forall w. NatRepr w -> Gen a)
    -- ^ generator for first arg
    -> (forall w. NatRepr w -> Gen a)
    -- ^ generator for second arg
    -> (forall w. NatRepr w -> a -> a -> a)
    -- ^ binary operator on domain
    -> (forall w. NatRepr w -> BV.BV w -> BV.BV w -> BV.BV w)
    -- ^ binary operator on codomain
    -> Property
bin genW p gen1 gen2 aOp bOp = property $ do
  Some w <- forAll genW
  a1 <- forAll (gen1 w)
  a2 <- forAll (gen2 w)

  -- compute f (a1 `aOp` a2)
  let a1_a2  = aOp w a1 a2
  let pa1_a2 = p w a1_a2

  -- compute f (a1) `bOp` f (a2)
  let pa1     = p w a1
  let pa2     = p w a2
  let pa1_pa2 = bOp w pa1 pa2
  
  pa1_a2 === pa1_pa2

binPred :: Show a
        => Gen (Some NatRepr)
        -- ^ generator for width
        -> (forall w. NatRepr w -> a -> BV.BV w)
        -- ^ morphism on domains
        -> (forall w . NatRepr w -> Gen a)
        -- ^ generator for first arg
        -> (forall w . NatRepr w -> Gen a)
        -- ^ generator for second arg
        -> (forall w . NatRepr w -> a -> a -> Bool)
        -- ^ binary predicate on domain
        -> (forall w . NatRepr w -> BV.BV w -> BV.BV w -> Bool)
        -- ^ binary predicate on codomain
        -> Property
binPred genW p gen1 gen2 aPred bPred = property $ do
  Some w <- forAll genW
  a1 <- forAll (gen1 w)
  a2 <- forAll (gen2 w)

  let a1_a2  = aPred w a1 a2

  let pa1     = p w a1
  let pa2     = p w a2
  let pa1_pa2 = bPred w pa1 pa2
  
  a1_a2 === pa1_pa2

----------------------------------------
-- Ranges

anyWidth :: Gen (Some NatRepr)
anyWidth = mkNatRepr <$> (Gen.integral $ Range.linear 0 128)

anyPosWidth :: Gen (Some NatRepr)
anyPosWidth = mkNatRepr <$> (Gen.integral $ Range.linear 1 128)

anyWidthGT1 :: Gen (Some NatRepr)
anyWidthGT1 = mkNatRepr <$> (Gen.integral $ Range.linear 2 128)

smallPosWidth :: Gen (Some NatRepr)
smallPosWidth = mkNatRepr <$> (Gen.integral $ Range.linear 1 4)

unsigned :: NatRepr w -> Gen Integer
unsigned w = Gen.integral $ Range.linear 0 (maxUnsigned w)

unsignedPos :: NatRepr w -> Gen Integer
unsignedPos w = Gen.integral $ Range.linear 1 (maxUnsigned w)

largeUnsigned :: NatRepr w -> Gen Integer
largeUnsigned w = Gen.integral $ Range.linear 0 (maxUnsigned w')
  where w' = incNat w

signed :: NatRepr w -> Gen Integer
signed w = case isZeroOrGT1 w of
  Left Refl -> error "Main.signed: w = 0"
  Right LeqProof -> Gen.integral $ Range.linearFrom 0 (minSigned w) (maxSigned w)

signedPos :: NatRepr w -> Gen Integer
signedPos w = case isZeroOrGT1 w of
  Left Refl -> error "Main.posBounded: w = 0"
  Right LeqProof -> Gen.integral $ Range.linear 1 (maxSigned w)

signedNeg :: NatRepr w -> Gen Integer
signedNeg w = case isZeroOrGT1 w of
  Left Refl -> error "Main.posBounded: w = 0"
  Right LeqProof -> Gen.integral $ Range.linearFrom (-1) (minSigned w) (-1)

largeSigned :: NatRepr w -> Gen Integer
largeSigned w = Gen.integral $ Range.linearFrom 0 (- maxUnsigned w') (maxUnsigned w')
  where w' = incNat w

genPair :: Gen a -> Gen a -> Gen (a, a)
genPair gen gen' = do
  a <- gen
  a' <- gen'
  return (a, a')

----------------------------------------
-- Tests

arithHomTests :: TestTree
arithHomTests = testGroup "arithmetic homomorphisms tests"
  [ testProperty "add" $ bin anyWidth BV.mkBV
    largeSigned largeSigned
    (const (+)) BV.add
  , testProperty "sub" $ bin anyWidth BV.mkBV
    largeSigned largeSigned
    (const (-)) BV.sub
  , testProperty "mul" $ bin anyWidth BV.mkBV
    largeSigned largeSigned
    (const (*)) BV.mul
  , testProperty "uquot" $ bin anyPosWidth BV.mkBV
    unsigned unsignedPos
    (const quot) (const BV.uquot)
  , testProperty "urem" $ bin anyPosWidth BV.mkBV
    unsigned unsignedPos
    (const rem) (const BV.urem)
  , testProperty "squot-pos-denom" $ bin anyWidthGT1 BV.mkBV
    signed signedPos
    (const quot) (forcePos BV.squot)
  , testProperty "squot-neg-denom" $ bin anyPosWidth BV.mkBV
    signed signedNeg
    (const quot) (forcePos BV.squot)
  , testProperty "srem-pos-denom" $ bin anyPosWidth BV.mkBV
    signed signedPos
    (const rem) (forcePos BV.srem)
  , testProperty "srem-neg-denom" $ bin anyPosWidth BV.mkBV
    signed signedNeg
    (const rem) (forcePos BV.srem)
  , testProperty "sdiv-pos-denom" $ bin anyPosWidth BV.mkBV
    signed signedPos
    (const div) (forcePos BV.sdiv)
  , testProperty "sdiv-neg-denom" $ bin anyPosWidth BV.mkBV
    signed signedNeg
    (const div) (forcePos BV.sdiv)
  , testProperty "smod-pos-denom" $ bin anyPosWidth BV.mkBV
    signed signedPos
    (const mod) (forcePos BV.smod)
  , testProperty "smod-neg-denom" $ bin anyPosWidth BV.mkBV
    signed signedNeg
    (const mod) (forcePos BV.smod)
  , testProperty "abs" $ un anyPosWidth BV.mkBV
    signed
    (const abs) (forcePos BV.abs)
  , testProperty "negate" $ un anyPosWidth BV.mkBV
    largeSigned
    (const negate) BV.negate
  , testProperty "signBit" $ un anyPosWidth BV.mkBV
    signed
    (\_ a -> if a < 0 then 1 else 0) (forcePos BV.signBit)
  , testProperty "slt" $ binPred anyPosWidth BV.mkBV
    signed signed
    (const (<)) (forcePos BV.slt)
  , testProperty "sle" $ binPred anyPosWidth BV.mkBV
    signed signed
    (const (<=)) (forcePos BV.sle)
  , testProperty "ult" $ binPred anyWidth BV.mkBV
    unsigned unsigned
    (const (<)) (const BV.ult)
  , testProperty "ule" $ binPred anyWidth BV.mkBV
    unsigned unsigned
    (const (<=)) (const BV.ule)
  , testProperty "umin" $ bin anyWidth BV.mkBV
    unsigned unsigned
    (const min) (const BV.umin)
  , testProperty "umax" $ bin anyWidth BV.mkBV
    unsigned unsigned
    (const max) (const BV.umax)
  ]

tests :: TestTree
tests = testGroup "bv-sized tests"
  [ arithHomTests
  ]

main :: IO ()
main = defaultMain arithHomTests
