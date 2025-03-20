// use std::time;
use std::time::Instant;

use ark_ec::{twisted_edwards::Projective, AdditiveGroup, AffineRepr, CurveGroup, PrimeGroup, VariableBaseMSM};
use ark_ff::{Field, FpConfig, PrimeField};
// use ark_bn254::{G1Projective as G, G1Affine as GAffine, Fr as ScalarField};
use ark_grumpkin::{Projective as G, Affine as GAffine, Fr as ScalarField};
use ark_std::{Zero, UniformRand};

const CONST: i64 = -17;

pub trait FromScaler: CurveGroup {
    fn scaler_to_curve_elt(x: Self::BaseField) -> Option<Self::Affine>;
    fn map_to_curve_one_shot(x: Self::BaseField) -> Option<(Self::Affine, Self::BaseField)>;
    fn map_to_curve(x: Self::BaseField, t_max: u64) -> Option<(Self::Affine, Self::BaseField, Self::BaseField)>;
}

impl FromScaler for G {
    fn scaler_to_curve_elt(x: Self::BaseField) -> Option<Self::Affine> {
        let x_cube = x.square() * x;
        let y_sq = x_cube + Self::BaseField::from(CONST);
        let y = y_sq.sqrt();
        if y.is_none() {
            None
        }
        else {
            let x_base = x;
            let y_base = y.unwrap();
            let out = Self::Affine::new_unchecked(x_base, y_base);
            Some(out)
        }
    }

    fn map_to_curve_one_shot(x: Self::BaseField) -> Option<(Self::Affine, Self::BaseField)> {
        let x_cube = x.square() * x;
        let y_sq = x_cube + Self::BaseField::from(CONST);
        let y = y_sq.sqrt();
        if y.is_none() {
            None
        }
        else {
            let x_base = x;
            let y_base = y.unwrap();
            let out = Self::Affine::new_unchecked(x_base, y_base);
            let z = y.unwrap().sqrt();
            if z.is_none() {
                return None;
            }
            Some((out, z.unwrap()))
        }   
    }

    fn map_to_curve(x: Self::BaseField, t_max: u64) -> Option<(Self::Affine, Self::BaseField, Self::BaseField)> {
        
        let mut little_t = 0;
        let big_t = Self::BaseField::from(t_max);

        while little_t < t_max {
            let field_t = Self::BaseField::from(little_t);
            let new_x = field_t + x*big_t;
            let x_cube = new_x.square() * new_x;
            let y_sq = x_cube + Self::BaseField::from(CONST);
            let y = y_sq.sqrt();
            
            if y.is_none() {
                little_t += 1;
            }
            else {
                let x_base = new_x;
                let y_base = y.unwrap();
                let out = Self::Affine::new_unchecked(x_base, y_base);
                let z = y.unwrap().sqrt();
                if z.is_some() {
                    return Some((out, z.unwrap(), field_t));
                }
                little_t += 1;
        }}
        None   
    }
}



fn main() {
    
    let start = Instant::now();
    let mut total = 0;
    for i in (1<<3)..(1<<7) {
        let x = <G as CurveGroup>::BaseField::from(i);
      
        let mapped_item = G::map_to_curve(x, 256);
        println!("msg: {:?}", i);
        println!("Multi try: {:?}", mapped_item);
        let curve_item = mapped_item.unwrap().0;
        let z_val = mapped_item.unwrap().1;
        println!("Z square = {:?}", z_val.square());
        println!("y_sq = {:?}", curve_item.y.square());
        println!("x_cube + {:?} = {:?}", CONST, curve_item.x.square() * curve_item.x + <G as CurveGroup>::BaseField::from(CONST));
        
        
        assert!(z_val.square() == curve_item.y);
        assert!(curve_item.is_on_curve());
        total += 1;
    }

    let duration = start.elapsed();
    println!("Time taken per search: {:?}", duration / total);

   
}
