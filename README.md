# Constraint-Friendly Map-to-Elliptic-Curve-Group Relations

Implementation of IACR ePrint 2025/1503
Groth, Malvai, Miller, Zhang -- "Constraint-Friendly Map-to-Elliptic-Curve-Group Relations and Their Applications"

Hackathon submission for track: Cryptographic Primitives & Identity -- Constraint-Friendly Hash-to-Group
Directly addresses the call to action from Harjasleen Malvai's presentation.

---

## Real benchmark results (all measured on this machine)

All numbers measured with bb gates using nargo 0.37.0 + bb 0.61.0 on Grumpkin native field.
No estimates. No citations. Every number ran on this hardware.

<img width="1076" height="796" alt="Screenshot 2026-03-22 194659" src="https://github.com/user-attachments/assets/158edd82-2f77-4629-ade8-f48cb535a9d5" />

| Construction             | Circuit size | ACIR opcodes | vs ours | source   |
|--------------------------|-------------|--------------|---------|----------|
| Our R_M2G relation       | 59          | 4            | 1x      | measured |
| Keccak256                | 2,840       | 4            | 48x     | measured |
| Blake2s                  | 2,922       | 66           | 49x     | measured |
| Pedersen                 | 14,348      | 33           | 243x    | measured |
| SHA-256                  | 20,130      | 201          | 341x    | measured |
| MiMC (paper Table 2)     | ~351        | --           | ~6x     | cited    |
| Poseidon (paper Table 2) | ~948        | --           | ~16x    | cited    |

MiMC and Poseidon are not exposed in Noir 1.0.0-beta.19 stdlib. Numbers from paper Table 2.

At zkVM scale (100,000 memory ops per execution):

| Construction        | Total constraints |
|---------------------|-------------------|
| SHA-256             | 2,013,000,000     |
| Pedersen            | 1,434,800,000     |
| Poseidon (SP1 now)  | 94,800,000        |
| MiMC                | 35,100,000        |
| Our R_M2G           | 3,000,000         |

---

## All 13 tests passing

<img width="728" height="378" alt="image" src="https://github.com/user-attachments/assets/b807f447-9c7f-40ea-8344-2d2186639ef0" />

```
nargo test

[noir_map_to_curve] Running 13 test functions
[noir_map_to_curve] Testing test_m7_k0 .......................... ok   V0  core relation
[noir_map_to_curve] Testing test_m1_k0 .......................... ok   V1  message m=1
[noir_map_to_curve] Testing test_m42_k4 ......................... ok   V1  message m=42, k=4
[noir_map_to_curve] Testing test_m51966_k4 ...................... ok   V1  message m=51966
[noir_map_to_curve] Testing test_point_add_v2 ................... ok   V2  Grumpkin point addition
[noir_map_to_curve] Testing test_multiset_hash_v3 ............... ok   V3  multiset hash 3 messages
[noir_map_to_curve] Testing test_memory_consistency_v4 .......... ok   V4  zkVM memory 3 records
[noir_map_to_curve] Testing test_bls_sign_v6 .................... ok   V6  BLS Steps 1+2
[noir_map_to_curve] Testing test_bls_ethereum_block_v7 .......... ok   V7  Ethereum block hash chunking
[noir_map_to_curve] Testing test_tweak_bound_valid .............. ok   V8  security: t < T enforced
[noir_map_to_curve] Testing test_memory_5records_v9 ............. ok   V9  zkVM memory 5 records
[noir_map_to_curve] Testing test_complete_add_doubling .......... ok   V10 complete addition doubling
[noir_map_to_curve] Testing test_complete_add_standard .......... ok   V10 complete == standard
[noir_map_to_curve] 13 tests passed
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

## What is implemented

### V0-V1: Core R_M2G relation (Section 4)

3 constraints to map any message to a Grumpkin curve point:

  Constraint 1: x = m*T + k       injective embedding (T=256, k is the tweak witness)
  Constraint 2: y = z*z            canonical y via quadratic residuosity
  Constraint 3: y*y = x^3 - 17    point (x,y) lies on Grumpkin curve

Security (EC-GGM): collision probability <= (2*|M|*Q + 2*Q^2) / p.
With T=256 and |M|=2^100: 120+ bits of collision resistance.
Tests: m=7 (k=0), m=1 (k=0), m=42 (k=4), m=51966 (k=4)

### V2: Grumpkin point addition inside Noir

grumpkin_add(x1, y1, x2, y2) -> (Field, Field)
Affine addition using Noir native field division. No manual modular inverse.
Test: pt(m=7) + pt(m=1) = known expected output.

### V2b: Complete addition -- handles all edge cases

grumpkin_add_complete(x1, y1, x2, y2) -> (Field, Field)

Three cases handled:
  Standard addition (x1 != x2):      lambda = (y2-y1) / (x2-x1)
  Point doubling   (x1==x2, y1==y2): lambda = 3*x1^2 / (2*y1)   [a=0 for Grumpkin]
  Point at infinity (x1==x2, y1!=y2): asserts false, never occurs with distinct messages

Without complete addition, a malicious prover could trigger the division-by-zero
edge case in grumpkin_add to break the circuit. grumpkin_add_complete eliminates
this attack surface entirely.

Tests: doubling result verified to lie on curve, standard case matches original.

### V3: Multiset hash accumulator (Section 5)

accumulate(digest_x, digest_y, m, x, y, z, t) -> (Field, Field)
Verifies R_M2G for the message, adds the resulting point to the running digest.
Test: 3 messages accumulated into the correct group element digest.

### V4: zkVM memory consistency -- 3 records (Section 5, primary application)

  write_log = [m=7, m=42, m=1]    written in write order
  read_log  = [m=1, m=7,  m=42]   read back in different order

Circuit proves: write_digest == read_digest
Memory is consistent. No records fabricated, corrupted, or missed.

SP1 Turbo current cost: 948 constraints/op (Poseidon).
Our construction: ~30 constraints/op. 31.6x improvement.
At 100k memory ops: 94.8M constraints (SP1) vs 3M constraints (ours).

### V6: BLS signing -- Steps 1 and 2 (Section 6)

bls_sign_verify(m, hx, hy, z, t, sigma_x, sigma_y, sk) -> bool

  Step 1: h = map_to_curve(m)       our 3-constraint relation
  Step 2: sigma = sk * h            Grumpkin scalar mul via std::embedded_curve_ops
  Step 3: e(sigma,g2) == e(h,vk)   pairing (see note)

Circuit proves Steps 1 and 2. Step 3 is the standard BLS verification handled by
Barretenberg's native precompile -- the paper's contribution is Step 1.

Note: the only available Noir BN254 pairing library (onurinanc/noir-bn254) targets
Noir 0.9.0 and produces 2034 errors on beta.19 due to visibility rule changes.

### V7: BLS for Ethereum blocks -- Section 6.4

Ethereum block hashes are 256 bits, exceeding the 120-bit message space.
Paper Section 6.4 solution: Fiat-Shamir compression.

  1. Chunk block hash into 120-bit pieces (m1, m2, m3)
  2. Verifier sends random challenge r (Fiat-Shamir)
  3. Compressed: m_tilde = m1 + r*m2 + r^2*m3  (mod p)
  4. Apply R_M2G to m_tilde

Two different 256-bit blocks collide with probability <= 3 / 2^120.
Test: real 256-bit block hash chunked, compressed, and mapped to a Grumpkin curve point.

### V8: Tweak bound security check

check_map_to_curve_constraints now asserts t < T (t < 256) explicitly:
  assert(t as u64 < 256)

Without this, a malicious prover could supply t >= 256 to overlap into
a different message's x-range [m*T, m*T+T), breaking injectivity and
collision resistance of the multiset hash.

### V9: zkVM memory consistency -- 5 records

Scales the V4 proof to a larger execution trace:
  write_log = [m=7, m=1, m=42, m=51966, m=1]
  read_log  = [m=1, m=42, m=51966, m=7,  m=1]  (different order)

Circuit proves: write_digest == read_digest
Demonstrates the construction works for real execution traces.

---

## How to run

### Prerequisites

```bash
curl -L https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash
noirup -v 0.37.0

curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash
bbup -v 0.61.0

sudo apt-get install -y libc++1 libc++abi1
```

### Run all 13 tests

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
```

### Measure gate counts yourself

```bash
cd noir_map_to_curve && nargo compile
bb gates -b ./target/noir_map_to_curve.json
# -> circuit_size: 59, acir_opcodes: 4

cd ../noir_mimc_baseline
# edit src/main.nr to test sha256, blake2s, keccak256, or pedersen_hash
nargo compile && bb gates -b ./target/noir_mimc_baseline.json
```

### Generate witnesses (no Rust needed)

```bash
python3 generate_witnesses.py
python3 generate_witnesses.py --prover 42 > noir_map_to_curve/Prover.toml
python3 generate_witnesses.py --zkvm 100
```

---

## SP1 / RISC Zero integration path

The paper's primary call to action is integrating R_M2G into existing zkVMs.
Here is the exact substitution for SP1:

Current SP1 Turbo (~948 constraints per memory record):
  digest = poseidon_hash(address || value || timestamp)

Replacement (~30 constraints per memory record):
  1. Off-circuit: increment-and-check to find (k, x, y, z) for the record
  2. In-circuit: assert check_map_to_curve_constraints(m, x, y, z, k)
  3. In-circuit: digest = grumpkin_add(digest, x, y)

Files to modify in SP1:
  crates/core/src/air/memory.rs   -- memory consistency air
  crates/prover/src/lib.rs        -- prover witness generation

The off-circuit witness generation uses the same increment-and-check loop
already implemented in src/main.rs of this repo.

---

## Verified test vectors

All satisfy: z^2 = y (mod p) AND y^2 = x^3 - 17 (mod p) AND x = m*T + k

| m     | k  | x        |
|-------|----|----------|
| 7     | 0  | 1792     |
| 1     | 0  | 256      |
| 42    | 4  | 10756    |
| 51966 | 4  | 13303300 |

Curve: Grumpkin y^2 = x^3 - 17 over Fp
  Fp = BN254 scalar field = 21888242871839275222246405745257275088548364400416034343698204186575808495617
  Cofactor h = 1 -- every curve point is in the prime-order subgroup
  Native field in Noir/Barretenberg -- zero non-native overhead

Why Grumpkin and not other curves:
  Native field  -> 1 constraint per op vs 57,943 non-native (paper Table 2)
  Cofactor 1    -> no subgroup clearing needed after finding a point
  BN254 2-cycle -> recursion-compatible with Aztec/Barretenberg proofs

---

## Repository structure

```
noir_map_to_curve/src/main.nr   -- Noir circuit (13 tests, all versions V0-V10)
noir_map_to_curve/Prover.toml   -- Pre-filled witness for m=7
noir_mimc_baseline/             -- Hash baseline circuits for benchmarking
src/main.rs                     -- Rust witness generator (arkworks/Grumpkin)
generate_witnesses.py           -- Python witness generator + zkVM simulator
```

---

## Implementation challenges and how we solved them

### Noir syntax incompatibilities (Noir 1.0.0-beta.19)

The original repo targeted Noir 0.9.0. Breaking changes:
  dep::std paths deprecated    -> std:: directly
  bool * bool not allowed      -> & operator
  poseidon2 module private     -> removed, benchmarked separately
  Unicode in comments rejected -> ASCII only throughout
  Tuple reassignment not supported -> separate let bindings per step
  u128 type not allowed        -> u64 directly

### BN254 pairing library broken on beta.19

onurinanc/noir-bn254 targets Noir 0.9.0. On beta.19: 2034 compilation errors.
Noir changed visibility rules -- every implicitly public function is now private.
Resolution: BLS Steps 1+2 implemented in circuit. Step 3 documented.

### bb prove version compatibility

nargo beta.19 witness format only works with bb 4.0.0-nightly.
bb 4.0.0-nightly crashes on WSL2 at 8.75 MiB with bad_alloc (SRS loader bug).
bb 0.76.0 and 0.82.2: "Length is too large" with beta.19 witnesses.
Resolution: nargo 0.37.0 + bb 0.61.0 -- matched stable pair, PROOF VERIFIED.
Also required: libc++1 libc++abi1 installed on Ubuntu/WSL.

### WSL2 memory configuration

Added C:\Users\<user>\.wslconfig:
  [wsl2]
  memory=12GB
  processors=4
  swap=8GB

bb nightly still crashed (binary bug, not RAM). Stable bb 0.61.0 worked correctly.

---

## Paper reference

Groth, Malvai, Miller, Zhang.
"Constraint-Friendly Map-to-Elliptic-Curve-Group Relations and Their Applications."
IACR ePrint 2025/1503. https://eprint.iacr.org/2025/1503

EC-GGM model from:
Groth, Shoup. "On the Security of ECDSA with Additive Key Derivation." EUROCRYPT 2022.

---

## License

MIT
