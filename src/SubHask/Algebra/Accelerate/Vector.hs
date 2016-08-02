module SubHask.Algebra.Accelerate.Vector
    (
    ValidACCVector
    , ACCVector (..)
    )
    where

import qualified Prelude as P

import Control.Monad.Primitive
import Control.Monad
import Data.Primitive hiding (sizeOf)
import Debug.Trace
import qualified Data.Primitive as Prim
import Foreign.Ptr
import Foreign.ForeignPtr
import Foreign.Marshal.Utils

import qualified Data.Array.Accelerate as A

import SubHask.Algebra
import SubHask.Algebra.Accelerate.AccelerateBackend (Backend)
import SubHask.Category
import SubHask.Algebra.Vector (SVector, type (+>))
import SubHask.Compatibility.Base
import SubHask.Internal.Prelude
import SubHask.SubType

import System.IO.Unsafe
import Unsafe.Coerce




--------------------------------------------------------------------------------

-- | Accelerate based Vector
-- | A.Acc is an accelreate computation, A.Array A.DIM1 a is a one dimensional array

newtype ACCVector (bknd::Backend) (n::k) a = ACCVector (A.Acc (A.Array A.DIM1 a))

type instance Scalar (ACCVector bknd n r) = Scalar (A.Acc(A.Scalar r))
type instance Logic (ACCVector bknd n r) = Logic (A.Acc(A.Scalar Bool))

type ValidACCVector bknd n a = (
                                 Prim a
                                , A.Elt a
                                , P.Num (A.Exp a)
                                , Scalar (A.Acc (A.Scalar a)) ~ A.Acc (A.Scalar a)
                                , Logic (A.Acc (A.Scalar a)) ~ A.Acc (A.Scalar a)
                                , Actor (A.Acc (A.Scalar a)) ~ A.Acc (A.Scalar a)
                                , Container (A.Acc (A.Scalar a))
                                , Container (Logic (A.Acc (A.Scalar Bool)))
                                , Boolean (Logic (A.Acc (A.Scalar Bool)))
                                , Logic (Logic (A.Acc (A.Scalar Bool))) ~  Logic (A.Acc (A.Scalar Bool))
                                , Logic (A.Acc (A.Scalar Bool)) ~ A.Acc (A.Scalar Bool)
                                , Elem (A.Acc (A.Scalar a)) ~ A.Acc (A.Scalar a)
                                , P.Fractional (A.Exp a)
                                , P.Floating (A.Exp a)
                                , P.Floating (A.Acc (A.Scalar a))
                                , P.Floating (A.Acc (A.Array A.DIM0 a))

                                )

type instance Index (ACCVector bknd n r) =  Index (A.Acc(A.Scalar Int))
type instance Elem (ACCVector bknd n r) =  Elem (A.Acc(A.Scalar r))

type instance Actor (ACCVector (bknd::Backend) n r) = Actor (A.Acc(A.Scalar r))

instance (KnownNat n, Prim a) => IsMutable (ACCVector (bknd::Backend) (n::Nat) a)

instance (KnownNat n, Monoid r, ValidACCVector b n r) => Semigroup (ACCVector (b::Backend) (n::Nat) r) where
    {-# INLINE (+)  #-}
    (+) :: ACCVector bknd n r -> ACCVector bknd n r -> ACCVector bknd n r
    (+) (ACCVector v1) (ACCVector v2)=ACCVector (A.zipWith (P.+) v1 v2)

instance (Semigroup  (Actor (A.Acc (A.Scalar r))), KnownNat n, ValidACCVector bknd n r, Action r, Semigroup r, Prim r) => Action (ACCVector (bknd::Backend) (n::Nat) r) where
    {-# INLINE (.+)   #-}
    (.+) (ACCVector v) r = ACCVector (A.map (A.+ (A.the r)) v)

instance (KnownNat n, Monoid r, Cancellative r, ValidACCVector bknd n r) => Cancellative (ACCVector (bknd::Backend) (n::Nat) r) where
    {-# INLINE (-)  #-}
    (-) (ACCVector a1) (ACCVector a2) = ACCVector (A.zipWith (P.-) a1 a2)

--The zero method wants a Ring r in the case where zero is the integer "0"
--or Field r in the case of "0.0"
--In either case, the Group instance wants the same constraint. Not exactly sure how to handle this.
instance (KnownNat n, Monoid r, ValidACCVector bknd n r) => Monoid (ACCVector (bknd::Backend) (n::Nat) r) where
--     {-# INLINE zero #-}
--     zero = ACCVector(A.use (A.fromList (A.Z A.:.1) [(0::r)]))

instance (KnownNat n, Group r, ValidACCVector bknd n r) => Group (ACCVector (bknd::Backend) (n::Nat) r) where
    {-# INLINE negate #-}
    negate = negate

instance (KnownNat n, Monoid r, Abelian r, ValidACCVector bknd n r) => Abelian (ACCVector (bknd::Backend)  (n::Nat) r)

instance (Ring  (A.Acc (A.Scalar r)), KnownNat n, FreeModule r, ValidACCVector bknd n r) => FreeModule (ACCVector (bknd::Backend)  (n::Nat) r) where
    {-# INLINE (.*.)   #-}
    (.*.) (ACCVector a1) (ACCVector a2) = ACCVector( A.zipWith (P.*) a1 a2)

instance (Ring  (A.Acc (A.Scalar r)), KnownNat n, Module r, ValidACCVector bknd n r) => Module (ACCVector (bknd::Backend) (n::Nat) r) where
    {-# INLINE (.*)   #-}
    (.*) (ACCVector  v) r = ACCVector (A.map (P.* (A.the r)) v)

instance (Field  (A.Acc (A.Scalar r)), KnownNat n, VectorSpace r, ValidACCVector bknd n r) => VectorSpace (ACCVector (bknd::Backend) (n::Nat) r) where
    {-# INLINE (./)   #-}
    (./) (ACCVector  v) r = ACCVector (A.map (P./ (A.the r)) v)

    {-# INLINE (./.)  #-}
    (./.) (ACCVector a1) (ACCVector a2) = ACCVector (A.zipWith (P./) a1 a2)

instance (Index (A.Acc (A.Scalar Int)) ~ A.Acc (A.Scalar Int), Ring (A.Acc (A.Scalar r)), KnownNat n, FreeModule r, ValidACCVector b n r) => FiniteModule (ACCVector b (n::Nat) r)
--dim wants an Int but here gets an A.Exp Int.  I tried changing the signiture to a generic type in Alegbra.hs but that produced numerous errors.
  where
    -- dim :: ACCVector b (n::Nat) r -> A.Exp Int
    -- {-# INLINE dim #-}
    -- dim (ACCVector v) = A.size v


instance
    ( Monoid r
    , ValidACCVector b n r
    , KnownNat n
    , Index (A.Acc (A.Scalar Int)) ~ A.Acc (A.Scalar Int)
    , FreeModule r
    ) => IxContainer (ACCVector b (n::Nat) r)
        where

    {-# INLINE (!) #-}
    (!) (ACCVector v) i = A.unit (v A.! A.index1 (A.the (i:: Index(A.Acc (A.Scalar Int)))))

    -- {-# INLINABLE imap #-}
    -- -- imap f (ACCVector v) = A.zipWith (\i x -> f ((A.unit i)::A.Acc (A.Scalar Int)) ((A.unit x)::A.Acc (A.Scalar r))) ((A.generate (A.shape v) P.id):: A.Array A.DIM1 Int) v
    -- imap f (ACCVector v) = let
    --   mapd = A.imap (\x (i::A.Exp r) -> let A.Z A.:. idx = A.unlift x -- This dance is probably not optimal but f expects A.Scalars so we have to build them
    --     in A.the (f  ((A.unit i) :: Index (ACCVector b n r)) (x ! idx))) v
    --   in ACCVector mapd

    type ValidElem (ACCVector b n r) e = (FiniteModule e, ValidACCVector b n e)

instance (A.Eq r, KnownNat n, Eq r, Monoid r, ValidACCVector b n r) => Eq (ACCVector b (n::Nat) r) where
    {-# INLINE (==) #-}
    (ACCVector v2) == (ACCVector v1) = let
      l = A.zipWith (\x y -> x A.==* y) v1 v2 :: A.Acc (A.Array A.DIM1 Bool)
      ele = l A.! A.index1 (A.constant 0)
      bl = A.all (A.&&* ele) l
      in bl

instance
    ( ValidACCVector b n r
    , A.Eq r
    , ExpField r
    , Ord (A.Acc (A.Scalar r))
    , Normed (A.Acc (A.Scalar r))
    , Ring (A.Acc (A.Scalar r))
    , Ord r
    , VectorSpace r
    , KnownNat n
    ) => Metric (ACCVector b (n::Nat) r)

        where
    {-# INLINE[2] distance #-}
    distance (ACCVector v1) (ACCVector v2) = {-# SCC distance_ACCVector #-}let
      dmag = A.zipWith (P.-) v1 v2
      dsq = A.zipWith (P.*) dmag dmag
      drt = A.sqrt (A.sum dsq)
      in drt

instance (Ring (A.Acc (A.Scalar r)), Ord (A.Acc (A.Scalar r)), Ord r,  KnownNat n, VectorSpace r, ValidACCVector b n r, ExpField r) => Normed (ACCVector b (n::Nat) r) where
    {-# INLINE size #-}
    size (ACCVector v1) = let
      sq = A.zipWith (P.*) v1 v1
      s = A.fold (P.+) (A.constant 0.0) sq
      srt = A.sqrt s
      in srt

instance
    ( VectorSpace r
    , A.Eq r
    , Normed r
    , Normed (A.Acc (A.Scalar r))
    , ValidACCVector b n r
    , Field (A.Acc (A.Scalar r))
    , Ord (A.Acc (A.Scalar r))
    , ExpField r
    , Real r
    , Ord r
    , KnownNat n
    ) => Banach (ACCVector b (n::Nat) r)

-- instance
--     ( FiniteModule (ACCVector b (n::Nat) r)
--     , VectorSpace (ACCVector b (n::Nat) r)
--     , Normed (ACCVector b n r +> ACCVector b n r)
--     , KnownNat n
--     , MatrixField r
--     ) => TensorAlgebra (ACCVector b (n::Nat) r)
--         where
--     (ACCVector v1)><(ACCVector v2) = let
--       r = A.size v1
--       c = A.size v2
--       arr = A.map (\i -> A.lift (A.map (\j -> i * j ) v1)) v2
--       m = A.reshape (A.index2 r c) arr :: ACCVector bknd n r +> ACCVector bknd m r
--       in m

instance
    ( VectorSpace r
    , ValidACCVector b n r
    , Ord (A.Acc (A.Scalar r))
    , Normed (A.Acc (A.Scalar r))
    , ExpField r
    , Real r
    , A.Eq r
    , OrdField r
    , Field (A.Acc (A.Scalar r))
    , MatrixField r
    , Rg (A.Exp r)
    , Semigroup (A.Exp r)
    , Field (A.Exp r)
    , KnownNat n
    , P.Num r
    ) => Hilbert (ACCVector b (n::Nat) r)
    where
    {-# INLINE (<>) #-}
    (<>) (ACCVector v1) (ACCVector v2) = let
      singlton = A.fold (+) 0.0 (A.zipWith (*) v1 v2) --This float-valued accumulator forces a Field (A.Exp r) constraint above.  Is there a way to formulate the constraints such that a more general zero-value could be used?
      in singlton


type MatrixField r =
    (
    VectorSpace r
    , Field r
    )