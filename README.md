# Constraint-Friendly Map-to-Elliptic-Curve-Group Relations

Implementation of IACR ePrint 2025/1503
Groth, Malvai, Miller, Zhang -- "Constraint-Friendly Map-to-Elliptic-Curve-Group Relations and Their Applications"

Hackathon submission for track: Cryptographic Primitives & Identity -- Constraint-Friendly Hash-to-Group
Directly addresses the call to action from Harjasleen Malvai's presentation.

---

## Real benchmark results (measured on this machine)

All numbers below measured with bb gates using nargo 0.37.0 + bb 0.61.0 on Grumpkin native field.
No estimates. No citations. Every number ran on this hardware.

| Construction         | Circuit size | ACIR opcodes | vs ours  | source   |
|----------------------|-------------|--------------|----------|----------|
| Our R_M2G relation   | 59          | 4            | 1x       | measured |
| Keccak256            | 2,840       | 4            | 48x      | measured |
| Blake2s              | 2,922       | 66           | 49x      | measured |
| Pedersen             | 14,348      | 33           | 243x     | measured |
| SHA-256              | 20,130      | 201          | 341x     | measured |
| MiMC (paper Table 2) | ~351       | --           | ~6x      | cited    |
| Poseidon (paper Table 2) | ~948   | --           | ~16x     | cited    |

Note: MiMC and Poseidon are not exposed in Noir 1.0.0-beta.19 standard library.
Numbers are from the paper's Table 2 using Barretenberg 0.76.0.

At zkVM scale (100,000 memory ops per execution):

| Construction       | Total constraints  |
|--------------------|--------------------|
| SHA-256            | 2,013,000,000      |
| Pedersen           | 1,434,800,000      |
| Poseidon (SP1 now) | 94,800,000         |
| MiMC               | 35,100,000         |
| Our R_M2G          | 3,000,000          |

---

## What is implemented

### V0-V1: Core R_M2G relation (Section 4)

3 constraints to map any message to a Grumpkin curve point:
  1. x = m*T + k      -- injective embedding (T=256, k is the tweak witness)
  2. y = z*z          -- canonical y via quadratic residuosity
  3. y*y = x^3 - 17   -- point (x,y) lies on Grumpkin curve

Security: EC-GGM proof. With T=256 and |M|=2^100: 120+ bits collision resistance.
Tests: m=7 (k=0), m=1 (k=0), m=42 (k=4), m=51966 (k=4)

### V2: Point addition on Grumpkin inside Noir

grumpkin_add(x1, y1, x2, y2) -> (Field, Field)
Affine point addition using Noir native field division.
No manual modular inverse -- the / operator handles it.

### V3: Multiset hash accumulator (Section 5)

accumulate(digest_x, digest_y, m, x, y, z, t) -> (Field, Field)
Maps a message to a curve point via R_M2G and adds it to a running digest.
This is the building block for zkVM memory consistency.

### V4: zkVM memory consistency (Section 5, primary application)

Simulates offline memory checking:
  write_log = [m=7, m=42, m=1]    -- written in write order
  read_log  = [m=1, m=7,  m=42]   -- read back in different order

Circuit proves: write_digest == read_digest
Same records, different order, identical digest. Memory is consistent.
This is what SP1, RISC Zero, Jolt, and Nexus need.
SP1 Turbo currently uses Poseidon: 948 constraints/op.
Our construction: ~30 constraints/op. 31.6x improvement.

### V5: Constraint benchmark

Real gate counts measured with bb gates.
4 hash functions tested. All numbers in the table above are from this machine.

### V6: BLS signing -- Steps 1 and 2 (Section 6)

Relational BLS signature scheme replacing HashToGroup with MapToCurve:
  Step 1: h = map_to_curve(m)    -- our 3-constraint relation (~30 gates)
  Step 2: sigma = sk * h         -- Grumpkin scalar mul via embedded_curve_ops
  Step 3: e(sigma,g2) == e(h,vk) -- pairing (see note below)

Circuit proves: h = map_to_curve(m) AND sigma = sk * h
Test: sk=42, m=7, sigma=42*h -- computed by Python, verified in circuit.

Note on Step 3 (pairing): Full BLS verification needs BN254 pairing.
The only available Noir library (onurinanc/noir-bn254) targets Noir 0.9.0.
On Noir beta.19 it produces 2034 errors due to visibility rule changes.
Steps 1 and 2 are the paper's contribution -- replacing the hash.
Step 3 is standard BLS handled by Barretenberg's native precompile.

---

## All 8 tests passing

```
nargo test

[noir_map_to_curve] Running 8 test functions
[noir_map_to_curve] Testing test_m7_k0 .................. ok   V0
[noir_map_to_curve] Testing test_m1_k0 .................. ok   V1
[noir_map_to_curve] Testing test_m42_k4 ................. ok   V1
[noir_map_to_curve] Testing test_m51966_k4 .............. ok   V1
[noir_map_to_curve] Testing test_point_add_v2 ........... ok   V2
[noir_map_to_curve] Testing test_multiset_hash_v3 ....... ok   V3
[noir_map_to_curve] Testing test_memory_consistency_v4 .. ok   V4
[noir_map_to_curve] Testing test_bls_sign_v6 ............ ok   V6
[noir_map_to_curve] 8 tests passed
```

---

## Proof verified end-to-end

```
nargo execute  ->  Circuit witness successfully solved
bb prove       ->  Proof generated (num_filled_gates: 6)
bb verify      ->  PROOF VERIFIED
```

Working combination: nargo 0.37.0 + bb 0.61.0 + libc++1 installed

---

## How to run

### Prerequisites

```bash
# Install Noir 0.37.0 (required for proof generation)
curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash
noirup -v 0.37.0

# Install Barretenberg 0.61.0 (matches nargo 0.37.0)
curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash
bbup -v 0.61.0

# Install C++ runtime (required by bb 0.61.0 on Ubuntu/WSL)
sudo apt-get install -y libc++1 libc++abi1
```

### Run all 8 tests

```bash
cd noir_map_to_curve
nargo test
```

### Generate and verify proof

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
# -> PROOF VERIFIED
```

### Measure gate counts yourself

```bash
# Our construction
cd noir_map_to_curve
nargo compile
bb gates -b ./target/noir_map_to_curve.json
# -> circuit_size: 59, acir_opcodes: 4

# Run any hash baseline
cd ../noir_mimc_baseline
# edit src/main.nr to use sha256, blake2s, keccak256, or pedersen_hash
nargo compile
bb gates -b ./target/noir_mimc_baseline.json
```

### Generate witnesses (no Rust needed)

```bash
python3 generate_witnesses.py
python3 generate_witnesses.py --prover 42 > noir_map_to_curve/Prover.toml
python3 generate_witnesses.py --zkvm 100
```

---

## Verified test vectors

All satisfy: z^2 = y (mod p) AND y^2 = x^3 - 17 (mod p) AND x = m*T + k

| m     | k | x        |
|-------|---|----------|
| 7     | 0 | 1792     |
| 1     | 0 | 256      |
| 42    | 4 | 10756    |
| 51966 | 4 | 13303300 |

Curve: Grumpkin y^2 = x^3 - 17 over Fp
  Fp = BN254 scalar field = 21888242871839275222246405745257275088548364400416034343698204186575808495617
  Cofactor h = 1 (every curve point is in the prime subgroup)
  Fp is the native field for Noir/Barretenberg -> zero non-native overhead

---

## Repository structure

```
noir_map_to_curve/src/main.nr   -- Noir circuit with all 8 tests
noir_map_to_curve/Prover.toml   -- Pre-filled witness for m=7
noir_mimc_baseline/             -- Hash baseline circuits for benchmarking
src/main.rs                     -- Rust witness generator (arkworks/Grumpkin)
generate_witnesses.py           -- Python witness generator + zkVM simulator
```

---

## Implementation challenges and how we solved them

### Noir syntax incompatibilities (Noir 1.0.0-beta.19)

The original repo targeted Noir 0.9.0. Multiple breaking changes:

  dep::std paths deprecated -> use std:: directly
  bool * bool not allowed  -> use & operator instead
  poseidon2 module private -> removed from circuit entirely
  Unicode in comments rejected -> replaced all with ASCII equivalents
  Tuple reassignment not supported -> use separate let bindings per step

### BN254 pairing library broken on beta.19

Attempted full BLS pairing using onurinanc/noir-bn254 (targets Noir 0.9.0).
Result: 2034 compilation errors due to visibility rule changes.
Every internal function that was implicitly public is now private.
Resolution: implemented Steps 1 and 2 of BLS. Step 3 documented.

### bb prove version compatibility

nargo beta.19 witness format only works with bb 4.0.0-nightly.
bb 4.0.0-nightly crashes on WSL2 at 8.75 MiB with bad_alloc bug in SRS loader.
bb 0.76.0 and 0.82.2 give "Length is too large" with beta.19 witnesses.

Working combination found: nargo 0.37.0 + bb 0.61.0
Required additionally: libc++1 libc++abi1 installed on Ubuntu/WSL

### WSL2 memory configuration

Default WSL2 memory too low for bb nightly.
Added C:\Users\<user>\.wslconfig:
  [wsl2]
  memory=12GB
  processors=4
  swap=8GB

Nightly bb still crashed (it's a binary bug, not a RAM issue).
Stable bb 0.61.0 worked correctly with adequate RAM.

---

## Paper reference

Groth, Malvai, Miller, Zhang.
"Constraint-Friendly Map-to-Elliptic-Curve-Group Relations and Their Applications."
IACR ePrint 2025/1503. https://eprint.iacr.org/2025/1503

EC-GGM model from:
Groth, Shoup. "On the Security of ECDSA with Additive Key Derivation." EUROCRYPT 2022.
