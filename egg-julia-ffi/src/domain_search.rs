// Domain-finding for a single-variable expression
//
// [0,0] = confirmed valid, [1,1] = confirmed invalid, [0,1] = ambiguous


use rival::{Ival, Machine, Discretization};
use crate::discretization::{to_ordinal, from_ordinal};

pub fn find_valid_domain<D: Discretization>(
    machine: &mut Machine<D>,
    start: Ival,
    depth: usize,
) -> (Vec<Ival>, Vec<Ival>) {
    let mut true_regions: Vec<Ival> = Vec::new();
    let mut other: Vec<Ival> = vec![start];
    let mut n = 0usize;

    loop {
        let explosion_cap = 1usize.checked_shl(depth.min(20) as u32).unwrap_or(usize::MAX);
        if n >= depth || other.is_empty() || other.len() >= explosion_cap {
            return (true_regions, other);
        }

        let mut next_other: Vec<Ival> = Vec::new();
        for region in other {
            let (status, _hint, converged) = machine.analyze_with_hints(&[region.clone()], None);
            let lo_valid = status.lo().is_zero();
            let hi_valid = status.hi().is_zero();
            let lo_invalid = *status.lo() == 1u32;
            let hi_invalid = *status.hi() == 1u32;

            // (searchreals.rkt)
            if lo_valid && hi_valid && converged {
                true_regions.push(region);
            } else if lo_invalid && hi_invalid {
                // 
            } else {
                // (Herbie's real two-midpoints, syntax/float.rkt),
                // Not (lo+hi)/2 -  (NaN) when lo/hi include infinity
                let lo_f64 = region.lo().to_f64();
                let hi_f64 = region.hi().to_f64();
                let lo_ord = to_ordinal(lo_f64) as i128;
                let hi_ord = to_ordinal(hi_f64) as i128;
                let mid_ord = ((lo_ord + hi_ord) / 2) as i64;
                let mid_f64 = from_ordinal(mid_ord);

                
                if mid_f64 <= lo_f64 || mid_f64 >= hi_f64 {
                    next_other.push(region);
                } else {
                    let mid = rug::Float::with_val(53, mid_f64);
                    let (left, right) = region.split_at(&mid);
                    next_other.push(left);
                    next_other.push(right);
                }
            }
        }

        other = next_other;
        n += 1;
    }
}
