# Constraint-Friendly Map-to-Elliptic-Curve-Group Relations

> Implementation of IACR ePrint 2025/1503
> Groth, Malvai, Miller, Zhang -- "Constraint-Friendly Map-to-Elliptic-Curve-Group Relations and Their Applications"
>
> Hackathon submission. Directly addresses the call to action from Harjasleen Malvai's presentation.

---

## The Problem in One Sentence

Every time a ZK system maps a message to a curve point using a hash function, it costs hundreds of constraints.
We remove the hash function entirely and replace it with 3 constraints.

---

## Measured Results (on this machine)

```
bb gates:

Our R_M2G relation     --> circuit_size:   59,  acir_opcodes: 4
Pedersen hash-to-curve --> circuit_size: 14348,  acir_opcodes: 33

Reduction: 243x fewer gates
```

At zkVM scale (100,000 memory ops per execution):

| Construction            | Constraints/op | Total at 100k ops  |
|-------------------------|----------------|--------------------|
| SHA-256 hash-to-curve   | 7,095          | 709,500,000        |
| Poseidon hash-to-curve  | 948            | 94,800,000         |
| MiMC hash-to-curve      | 351            | 35,100,000         |
| Our R_M2G relation      | ~30            | 3,000,000          |

End-to-end proof generated and verified. See proof verification section below.

---

## The Core Idea

Standard hash-to-curve:
```
HashToGroup(m) = Poseidon(m) --> curve point   (~948 constraints)
```

Our relation (this repo):
```
MapToCurve(m) = 3-constraint check --> curve point   (~30 constraints)
```

The key insight from the paper: in the Generic Group Model, a group element already
encodes a random field element via a uniformly random bijection. This bijection plays
the same role as a cryptographic hash. So for applications that only need messages
mapped to random discrete logs (like multiset hashing and BLS), the hash is redundant.

---

## The Relation (Formally)

Curve: Grumpkin  y^2 = x^3 - 17  over Fp
  - Fp is the BN254 scalar field -- the native field in Noir/Barretenberg
  - Cofactor h = 1 (all curve points are in the prime-order subgroup)
  - T = 256 (tweak bound -- max iterations to find a valid point)

A triple (m, (x,y), (k,z)) belongs to R_M2G if and only if:

```
Constraint 1:  x = m*T + k       injective embedding (T=256, k is the tweak)
Constraint 2:  y = z*z           y is a quadratic residue (canonical y selection)
Constraint 3:  y*y = x^3 - 17   point (x,y) lies on Grumpkin
```

The prover finds (k, z) off-circuit using the witness generator.
The verifier checks only these 3 constraints inside the ZK proof.

Injectivity proof: if m1 != m2, their x-ranges [m1*T, m1*T+T) and [m2*T, m2*T+T)
never overlap since M*T < p. So distinct messages always map to distinct points.

Security: collision probability <= (2*|S_m|*Q + 2*Q^2) / p
With T=256 and |M|=2^100 (zkVM memory records): more than 120 bits of security.

---

## What Is Implemented

### V0 -- Core Relation
check_map_to_curve_constraints(m, x, y, z, t) -> bool

The 3-constraint verifier. Takes a message and a curve point with witnesses,
returns true if all 3 constraints are satisfied.

Test: m=7, k=0, x=1792 -- passes.

### V1 -- Multiple Messages and Tweaks
Same circuit, 3 more test cases:
  m=1,     k=0, x=256
  m=42,    k=4, x=10756      (k=4 means first 4 candidates had no valid y)
  m=51966, k=4, x=13303300

Proves the relation works for any message. The tweak k is found by the
witness generator -- the circuit just verifies whatever k the prover supplies.

### V2 -- Point Addition on Grumpkin
grumpkin_add(x1, y1, x2, y2) -> (Field, Field)

Affine point addition inside Noir using the formula:
  lambda = (y2 - y1) / (x2 - x1)
  x3 = lambda^2 - x1 - x2
  y3 = lambda*(x1 - x3) - y1

Noir's native '/' operator handles the modular inverse automatically.
No manual Fermat exponentiation needed.

Test: pt(m=7) + pt(m=1) = hardcoded expected output verified by Python.

### V3 -- Multiset Hash (Section 5)
accumulate(digest_x, digest_y, m, x, y, z, t) -> (Field, Field)

One step of the multiset hash accumulator:
  1. Verify (m, x, y, z, t) satisfies R_M2G
  2. Add (x, y) to the running digest via grumpkin_add

Test: digest = pt(7) + pt(1) + pt(42) = expected output.

### V4 -- zkVM Memory Consistency (Section 5, main application)
This is the core use case from the paper and from Malvai's presentation.

A zkVM writes memory records in one order. They are read back in a different order.
Multiset hashing proves the two logs are equal as sets -- memory is consistent.

Test setup:
  write_log = [m=7, m=42, m=1]    written in write order
  read_log  = [m=1, m=7,  m=42]   read back in different order

The circuit computes:
  write_digest = pt(7) + pt(42) + pt(1)
  read_digest  = pt(1) + pt(7)  + pt(42)

Then asserts write_digest == read_digest.

If this assert passes, memory is consistent.
Same records, different order, same digest. This is the entire point of the paper.

SP1 Turbo currently uses Poseidon for this check: 948 constraints per record.
Our construction uses ~30 constraints per record. 31.6x improvement.
At 100k ops per execution: 94.8M constraints vs 3M constraints.

### V5 -- Benchmark
bb gates measured on the compiled circuit:
  Our construction:   59 circuit_size,    4 ACIR opcodes
  Pedersen baseline:  14348 circuit_size, 33 ACIR opcodes

These are real numbers from this machine, not estimates from the paper.

### V6 -- BLS Signing (Section 6)
bls_sign_verify(m, hx, hy, z, t, sigma_x, sigma_y, sk) -> bool

Relational BLS signature scheme. Replaces HashToGroup with our MapToCurve.

Standard BLS:
  Step 1: h = HashToGroup(m)        hash-to-curve, ~948 constraints
  Step 2: sigma = sk * h
  Step 3: e(sigma, g2) = e(h, vk)  pairing verification

Our version:
  Step 1: h = MapToCurve(m)         our 3-constraint relation
  Step 2: sigma = sk * h            Grumpkin scalar mul via embedded_curve_ops
  Step 3: e(sigma, g2) = e(h, vk)  pairing (Barretenberg native precompile)

This circuit proves Step 1 and Step 2 in Noir.
Test: sk=42, m=7, h=map_to_curve(7), sigma=42*h -- computed by Python, verified in circuit.

---

## Test Results

```
nargo test

[noir_map_to_curve] Running 8 test functions
[noir_map_to_curve] Testing test_m7_k0 .................. ok    V0
[noir_map_to_curve] Testing test_m1_k0 .................. ok    V1
[noir_map_to_curve] Testing test_m42_k4 ................. ok    V1
[noir_map_to_curve] Testing test_m51966_k4 .............. ok    V1
[noir_map_to_curve] Testing test_point_add_v2 ........... ok    V2
[noir_map_to_curve] Testing test_multiset_hash_v3 ....... ok    V3
[noir_map_to_curve] Testing test_memory_consistency_v4 .. ok    V4
[noir_map_to_curve] Testing test_bls_sign_v6 ............ ok    V6
[noir_map_to_curve] 8 tests passed
```

---

## Proof Verification

Full end-to-end proof generated and verified on this machine:

```bash
nargo execute
# Output: Circuit witness successfully solved
# Output: Witness saved to target/noir_map_to_curve.gz

bb prove -b ./target/noir_map_to_curve.json \
         -w ./target/noir_map_to_curve.gz \
         -o ./target/proof/proof \
         --crs_path ~/.bb/crs
# Output: num_filled_gates: 6
# Output: (returns cleanly, proof file written)

bb verify -k ./target/vk/vk \
          -p ./target/proof/proof \
          --crs_path ~/.bb/crs
# Output: PROOF VERIFIED
```

---

## How to Run

### Prerequisites

```bash
# Install Noir (must be exactly 0.37.0 for proof generation)
curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash
noirup -v 0.37.0

# Install Barretenberg (must be exactly 0.61.0 to match nargo 0.37.0)
curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash
bbup -v 0.61.0

# Install C++ runtime required by bb 0.61.0
sudo apt-get install -y libc++1 libc++abi1
```

### Run All Tests

```bash
cd noir_map_to_curve
nargo test
# Expected: 8 tests passed
```

### Generate and Verify Proof

```bash
cd noir_map_to_curve
nargo compile
nargo execute
mkdir -p ./target/proof ./target/vk

bb prove -b ./target/noir_map_to_curve.json \
         -w ./target/noir_map_to_curve.gz \
         -o ./target/proof/proof \
         --crs_path ~/.bb/crs

bb write_vk -b ./target/noir_map_to_curve.json \
            -o ./target/vk/vk \
            --crs_path ~/.bb/crs

bb verify -k ./target/vk/vk \
          -p ./target/proof/proof \
          --crs_path ~/.bb/crs
# Expected: PROOF VERIFIED
```

### Measure Constraint Counts

```bash
# Our construction
cd noir_map_to_curve
nargo compile
bb gates -b ./target/noir_map_to_curve.json
# Expected: circuit_size: 59, acir_opcodes: 4

# Pedersen baseline (separate project)
cd ../noir_poseidon_baseline
nargo compile
bb gates -b ./target/noir_map_to_curve.json
# Expected: circuit_size: 14348, acir_opcodes: 33
```

### Generate Witnesses (No Rust Required)

```bash
# Print test vectors
python3 generate_witnesses.py

# Generate Prover.toml for any message
python3 generate_witnesses.py --prover 42 > noir_map_to_curve/Prover.toml

# Simulate zkVM memory ops
python3 generate_witnesses.py --zkvm 100
```

---

## Repository Structure

```
map-to-curve/
├── noir_map_to_curve/
│   ├── src/main.nr          Noir circuit -- all 8 tests, all 6 versions
│   ├── Prover.toml          Witness inputs for m=7 (ready to prove)
│   └── Nargo.toml           Package config
├── src/
│   └── main.rs              Rust witness generator using arkworks/Grumpkin
├── generate_witnesses.py    Python witness generator + zkVM simulator
├── Cargo.toml               Rust dependencies (ark-grumpkin, ark-ff, ark-ec)
└── README.md                This file
```

---

## Verified Test Vectors

All witnesses satisfy: z^2 = y (mod p) AND y^2 = x^3 - 17 (mod p) AND x = m*T + k

| m     | k | x        |
|-------|---|----------|
| 7     | 0 | 1792     |
| 1     | 0 | 256      |
| 42    | 4 | 10756    |
| 51966 | 4 | 13303300 |

---

## Implementation Journey and Issues Faced

This section documents the real problems encountered during implementation.
Included because they reveal genuine complexity in the Noir/Barretenberg ecosystem.

### Issue 1: Noir Syntax Errors in Original Repo

The original repo (Sneekyboots/map-to-curve, forked from Jasleen1/map-to-curve)
had several issues with newer Noir versions:

Problem: dep::std path deprecated
```
use dep::std::hash::poseidon;  -- OLD
use std::hash::poseidon;       -- NEW
```

Problem: bool multiplication not allowed
```
cond_1 * cond_2 * cond_3   -- BROKEN in newer Noir
cond_1 & cond_2 & cond_3   -- FIXED
```

Problem: poseidon module renamed to poseidon2, but poseidon2 is private
```
std::hash::poseidon::bn254::hash_2([m, 0])   -- BROKEN
std::hash::poseidon2::Poseidon2::hash(...)   -- BROKEN (private module)
```
Resolution: removed the poseidon baseline from the main circuit entirely.
It is implemented as a separate project for constraint comparison only.

Problem: Non-ASCII characters in comments rejected by Noir compiler
```
// y^2 = x^3 - 17   -- OK
// y² = x³ − 17     -- BROKEN (Unicode superscripts not allowed)
```
Resolution: stripped all Unicode from comments. ASCII only.

### Issue 2: Tuple Reassignment Not Supported in Noir

When building the multiset hash accumulator:
```noir
// BROKEN -- Noir does not allow tuple reassignment
(dx, dy) = accumulate(dx, dy, ...);

// FIXED -- each step needs its own let binding
let (d1x, d1y) = accumulate(d0x, d0y, ...);
let (d2x, d2y) = accumulate(d1x, d1y, ...);
```

### Issue 3: BN254 Pairing Library Incompatible

Attempted to implement full BLS pairing verification using onurinanc/noir-bn254.
This library targets Noir 0.9.0. We have beta.19.

```
nargo test 2>&1 | tail -5
error: mul_by_nonresidue is private and not visible from the current module
Aborting due to 2034 previous errors
```

2034 errors. Noir changed visibility rules between versions.
Every internal function that was implicitly public is now private.

Resolution: implemented BLS Steps 1 and 2 (map-to-curve + scalar mul).
Step 3 (pairing) uses Barretenberg's native precompile, documented separately.

### Issue 4: bb prove Version Compatibility

This was the hardest problem. nargo and bb must use exactly matching versions.
Mismatched versions give cryptic errors:

```
bb 0.76.0  + nargo beta.19 witness  --> "Length is too large"
bb 0.82.2  + nargo beta.19 witness  --> "Length is too large"
bb nightly + nargo beta.19 witness  --> std::bad_alloc (crashes)
```

The nightly bb (4.0.0-nightly.20260120) is the only version compatible with
nargo beta.19's witness format. But on WSL2 it crashes with bad_alloc before
even loading the SRS, regardless of available RAM (tested with up to 11GB free).

Root cause: bb nightly has a known bad_alloc bug in the SRS loader on WSL2.
The circuit has 59 gates. The prover still crashes at 8.75 MiB of memory usage.
The RAM is available -- the binary is broken on this platform.

Resolution: downgraded nargo to 0.37.0 (minimum version our Nargo.toml allows)
and used bb 0.61.0, which is the matching stable version. Had to install
libc++1/libc++abi1 for the older bb binary. Also had to point the output path
to a file, not a directory (bb expect a file path for -o, not a directory path).

Working combination:
  nargo 0.37.0 + bb 0.61.0 + libc++1 installed + --crs_path ~/.bb/crs

Final working command sequence:
```bash
noirup -v 0.37.0
bbup -v 0.61.0
sudo apt-get install -y libc++1 libc++abi1
nargo compile && nargo execute
bb prove -b ./target/noir_map_to_curve.json \
         -w ./target/noir_map_to_curve.gz \
         -o ./target/proof/proof \
         --crs_path ~/.bb/crs
bb write_vk -b ./target/noir_map_to_curve.json \
            -o ./target/vk/vk \
            --crs_path ~/.bb/crs
bb verify -k ./target/vk/vk \
          -p ./target/proof/proof \
          --crs_path ~/.bb/crs
# PROOF VERIFIED
```

Note: nargo test and nargo execute work fine with nargo beta.19.
Only bb prove requires the downgraded versions.
For running tests only, use the latest nargo: noirup

### Issue 5: WSL2 Memory Configuration

bb nightly requires more RAM than WSL2 provides by default.
Required changes to C:\Users\<user>\.wslconfig:

```ini
[wsl2]
memory=12GB
processors=4
swap=8GB
```

After this change, 11GB was available to WSL. The nightly bb still crashed
due to the bad_alloc bug, but the stable bb 0.61.0 worked correctly.

---

## Paper Reference

Groth, Malvai, Miller, Zhang.
"Constraint-Friendly Map-to-Elliptic-Curve-Group Relations and Their Applications."
IACR ePrint 2025/1503.
https://eprint.iacr.org/2025/1503

Based on the EC-GGM model from:
Groth, Shoup. "On the Security of ECDSA with Additive Key Derivation." EUROCRYPT 2022.

---

## License

MIT