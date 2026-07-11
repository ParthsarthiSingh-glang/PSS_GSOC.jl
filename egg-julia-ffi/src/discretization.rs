// Discretization for f64, rival3-ffi/src/discretization.rs

use rival::Discretization;
use rug::Float;

pub struct Fp64Discretization;

impl Clone for Fp64Discretization {
    fn clone(&self) -> Self {
        Fp64Discretization
    }
}

impl Discretization for Fp64Discretization {
    #[inline]
    fn target(&self) -> u32 {
        53
    }

    #[inline]
    fn convert(&self, _idx: usize, v: &Float) -> Float {
        Float::with_val(53, v.to_f64())
    }

    #[inline]
    fn distance(&self, _idx: usize, lo: &Float, hi: &Float) -> usize {
        ordinal_distance_f64(lo.to_f64(), hi.to_f64())
    }
}

#[inline]
fn ordinal_distance_f64(x: f64, y: f64) -> usize {
    if x == y {
        return 0;
    }
    to_ordinal(y).wrapping_sub(to_ordinal(x)).unsigned_abs() as usize
}

//  ordinal conversion (Racket flonum->ordinal / our own flonums_between in sampling.jl)
#[inline]
pub(crate) fn to_ordinal(v: f64) -> i64 {
    if v == 0.0 {
        return 0;
    }
    let bits = v.to_bits() as i64;
    if bits < 0 { i64::MIN.wrapping_sub(bits) } else { bits }
}

#[inline]
pub(crate) fn from_ordinal(o: i64) -> f64 {
    if o == 0 {
        return 0.0;
    }
    let bits: u64 = if o < 0 { i64::MIN.wrapping_sub(o) as u64 } else { o as u64 };
    f64::from_bits(bits)
}
