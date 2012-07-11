{-# LANGUAGE CPP #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Main where

import Prelude hiding (map)

import Data.Vector.Storable (Vector)
import Language.C.Quote.CUDA
import qualified Language.C.Syntax as C

#if !MIN_VERSION_template_haskell(2,7,0)
import qualified Data.Loc
import qualified Data.Symbol
import qualified Language.C.Syntax
#endif /* !MIN_VERSION_template_haskell(2,7,0) */

import CUDA.Context
import Nikola
import Nikola.Embeddable

main :: IO ()
main = withNewContext $ \_ -> do
    test

test :: IO ()
test = do
    print (g v)
  where
    g :: Vector Float -> Vector Float
    g = compile f2

    v :: Vector Float
    v = fromList [0..32]

f :: Exp (Vector Float) -> Exp (Vector Float)
f = map inc

inc :: Exp Float -> Exp Float
inc = vapply $ \x -> x + 1

f2 :: CFun (Exp (Vector Float) -> Exp (Vector Float))
f2 = CFun { cfunName = "f2"
          , cfunDefs = defs
          , cfunAllocs = [VectorT FloatT nmin]
          , cfunExecConfig = ExecConfig { gridDimX  = fromIntegral 240
                                        , gridDimY  = 1
                                        , blockDimX = fromIntegral 128
                                        , blockDimY = 1
                                        , blockDimZ = 1
                                        }
          }
  where
    nmin :: N
    nmin = NVecLength 0

    defs :: [C.Definition]
    defs = [cunit|
__device__ float f0(float x2)
{
    float v4;

    v4 = x2 + 1.0F;
    return v4;
}
extern "C" __global__ void f2(float* x0, int x0n, float* temp, long long* tempn)
{
    for (int i = (blockIdx.x + blockIdx.y * gridDim.x) * 128 + threadIdx.x; i <
         x0n; i += 128 * 240) {
        if (i < x0n) {
            {
                float temp0;

                temp0 = f0(x0[i]);
                temp[i] = temp0;
            }
            if (i == 0)
                *tempn = x0n;

        }
    }
    __syncthreads();
}
      |]