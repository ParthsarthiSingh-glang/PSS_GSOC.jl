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
        let explosion_cap = 1usize.checked_shl(depth as u32).unwrap_or(usize::MAX);
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

// binary-search (searchreals.rkt):
fn binary_search(weights_cumsum: &[u128], num: u128) -> usize {
    let mut left = 0usize;
    let mut right = weights_cumsum.len() - 1;
    while left < right {
        let mid = (left + right) / 2; 
        let pivot = weights_cumsum[mid];
        if pivot <= num {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    left.min(weights_cumsum.len() - 1)
}

// Weighted sampling
pub fn sample_points<D: Discretization>(
    machine: &mut Machine<D>,
    regions: &[Ival],
    n: usize,
) -> Result<Vec<(f64, f64)>, String> {
    use rand::Rng;
    let mut rng = rand::rng();
    const MAX_SKIPPED_POINTS: usize = 100;

    let weights: Vec<u128> = regions
        .iter()
        .map(|r| {
            let lo_ord = to_ordinal(r.lo().to_f64()) as i128;
            let hi_ord = to_ordinal(r.hi().to_f64()) as i128;
            (1 + (hi_ord - lo_ord)) as u128
        })
        .collect();

    // hyperrect-sampler 
    let mut weights_cumsum: Vec<u128> = Vec::with_capacity(weights.len());
    let mut running = 0u128;
    for &w in &weights {
        running += w;
        weights_cumsum.push(running);
    }
    let weight_max = *weights_cumsum.last().unwrap();

    let mut results = Vec::new();
    let mut skipped = 0usize;

    while results.len() < n {
        // (define idx (binary-search weights (random-natural weight-max)))
        let num = rng.random_range(0..weight_max);
        let idx = binary_search(&weights_cumsum, num);
        let chosen = &regions[idx];

        let lo_ord = to_ordinal(chosen.lo().to_f64());
        let hi_ord = to_ordinal(chosen.hi().to_f64());
        let point_ord = rng.random_range(lo_ord..=hi_ord);
        let point_f64 = from_ordinal(point_ord);

        // is-bad? check 
        if point_f64.is_nan() {
            skipped += 1;
            if skipped >= MAX_SKIPPED_POINTS {
                return Err("Cannot sample enough valid points.".to_string());
            }
            continue;
        }

        let point = rug::Float::with_val(53, point_f64);
        let arg = Ival::from_lo_hi(point.clone(), point);

        match machine.apply(&[arg], None, 5) {
            Ok(out) => {
                let r = &out[0];
                results.push((point_f64, (r.lo().to_f64() + r.hi().to_f64()) / 2.0));
                skipped = 0; // reset on success, matching Herbie exactly
            }
            Err(_) => {
                skipped += 1;
                if skipped >= MAX_SKIPPED_POINTS {
                    return Err("Cannot sample enough valid points.".to_string());
                }
            }
        }
    }

    Ok(results)
}
