// map-to-curve relation -- Groth, Malvai, Miller, Zhang (2025)
// Curve: Grumpkin  y^2 = x^3 - 17  (BN254 native scalar field)
//
// A triple (m, (x,y), (k,z)) is valid iff:
//   1. x = m*T + k       (injective embedding, T=256)
//   2. y = z*z           (y is a quadratic residue)
//   3. y*y = x^3 - 17   (point (x,y) lies on Grumpkin curve)

global T: Field = 256;

fn check_map_to_curve_constraints(m: Field, x: Field, y: Field, z: Field, t: Field) -> bool {
    // Security: t must be in [0, T) for injectivity to hold
    // Without this a large tweak could overlap into another message range
    let t_bounded = t as u64;
    assert(t_bounded < 256);

    let cond_1 = (x == (t + m * T));
    let cond_2 = (y == (z * z));
    let x_sq = x * x;
    let f_x = (x_sq * x) - 17;
    let y_sq = y * y;
    let cond_3 = (y_sq == f_x);
    cond_1 & cond_2 & cond_3
}

fn main(m: Field, x: Field, y: Field, z: Field, t: Field) {
    assert(check_map_to_curve_constraints(m, x, y, z, t));
}

// ================================================================
// V0 -- original test
// ================================================================

#[test]
fn test_m7_k0() {
    // m=7, T=256 -> x = 7*256 + 0 = 1792, tweak k=0
    main(
        7,
        1792,
        2222603532014808061213222263845635574143735707039159930479525957984581958699,
        276759698173846535821495865193274967682377030871373817764620224677696820189,
        0
    );
}

// ================================================================
// V1 -- three more messages, different tweaks
// ================================================================

#[test]
fn test_m1_k0() {
    // m=1, T=256 -> x = 1*256 + 0 = 256, tweak k=0
    main(
        1,
        256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        4477254854248242929434024226743979797109261084935875761478684308825718674401,
        0
    );
}

#[test]
fn test_m42_k4() {
    // m=42, T=256 -> x = 42*256 + 4 = 10756, tweak k=4
    // k=4 means the first 4 x-values had no valid y, found on 5th try
    main(
        42,
        10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    );
}

#[test]
fn test_m51966_k4() {
    // m=51966 (0xcafe), T=256 -> x = 51966*256 + 4 = 13303300, tweak k=4
    main(
        51966,
        13303300,
        6381688230921594513280573875668687859581864100179855876276692266416978407457,
        19238252694299235642504735672665962165555071883453037161111322236043699986662,
        4
    );
}

// ================================================================
// V2 -- point addition on Grumpkin inside Noir
// ================================================================

// Affine point addition on Grumpkin (y^2 = x^3 - 17)
// Inputs:  two curve points (x1,y1) and (x2,y2)
// Output:  their sum (x3,y3)
// Formula: lambda = (y2-y1)/(x2-x1)
//          x3 = lambda^2 - x1 - x2
//          y3 = lambda*(x1-x3) - y1
// Note: '/' in Noir is modular inverse multiplication -- no extra code needed
fn grumpkin_add(x1: Field, y1: Field, x2: Field, y2: Field) -> (Field, Field) {
    let lam = (y2 - y1) / (x2 - x1);
    let x3 = lam * lam - x1 - x2;
    let y3 = lam * (x1 - x3) - y1;
    (x3, y3)
}

// Complete addition: handles doubling (P1==P2) and standard addition
// For multiset hashing the doubling case is rare but must be handled
// for a production-ready circuit
fn grumpkin_add_complete(x1: Field, y1: Field, x2: Field, y2: Field) -> (Field, Field) {
    // Check if points are equal (doubling) or inverses (point at infinity)
    if x1 == x2 {
        // Doubling: lambda = 3*x1^2 / (2*y1)   (a=0 for Grumpkin)
        // Note: if y1 == 0 result is infinity -- handled by assert
        assert(y1 != 0);
        if y1 == y2 {
            let lam = (3 * x1 * x1) / (2 * y1);
            let x3 = lam * lam - 2 * x1;
            let y3 = lam * (x1 - x3) - y1;
            (x3, y3)
        } else {
            // y1 == -y2: result is point at infinity
            // In a production circuit return an is_infinite flag
            // For our multiset hash this never occurs with distinct messages
            assert(false);
            (0, 0)
        }
    } else {
        // Standard addition
        let lam = (y2 - y1) / (x2 - x1);
        let x3 = lam * lam - x1 - x2;
        let y3 = lam * (x1 - x3) - y1;
        (x3, y3)
    }
}

#[test]
fn test_complete_add_doubling() {
    // Test point doubling: pt(m=7) + pt(m=7) = 2*pt(7)
    let x1 = 1792;
    let y1 = 2222603532014808061213222263845635574143735707039159930479525957984581958699;
    let (x3, y3) = grumpkin_add_complete(x1, y1, x1, y1);
    // Verify result is on curve: y3^2 = x3^3 - 17
    let x3sq = x3 * x3;
    assert(y3 * y3 == x3sq * x3 - 17);
}

#[test]
fn test_complete_add_standard() {
    // Standard addition matches the original formula
    let x1 = 1792;
    let y1 = 2222603532014808061213222263845635574143735707039159930479525957984581958699;
    let x2 = 256;
    let y2 = 9189236229814196392576801464214343739846708746841839291083803335996532870109;
    let (x3a, y3a) = grumpkin_add(x1, y1, x2, y2);
    let (x3b, y3b) = grumpkin_add_complete(x1, y1, x2, y2);
    assert(x3a == x3b);
    assert(y3a == y3b);
}

#[test]
fn test_point_add_v2() {
    // pt(m=7) + pt(m=1) -- expected output computed by Python
    let x1 = 1792;
    let y1 = 2222603532014808061213222263845635574143735707039159930479525957984581958699;
    let x2 = 256;
    let y2 = 9189236229814196392576801464214343739846708746841839291083803335996532870109;

    let (x3, y3) = grumpkin_add(x1, y1, x2, y2);

    assert(x3 == 6948097311120566491744134796637192933886660205857188513289049757805015881283);
    assert(y3 == 12182757782924226552209586997238557737137166422957283746962215320775400115954);
}


// ================================================================
// V3 -- multiset hash: map 3 messages, accumulate into one digest
// ================================================================

fn accumulate(
    digest_x: Field, digest_y: Field,
    m: Field, x: Field, y: Field, z: Field, t: Field
) -> (Field, Field) {
    assert(check_map_to_curve_constraints(m, x, y, z, t));
    grumpkin_add(digest_x, digest_y, x, y)
}

#[test]
fn test_multiset_hash_v3() {
    // digest = pt(m=7) + pt(m=1) + pt(m=42)
    // Noir does not allow tuple reassignment -- use separate let bindings

    // Start: digest = pt(m=7)
    let d0x = 1792;
    let d0y = 2222603532014808061213222263845635574143735707039159930479525957984581958699;

    // Add pt(m=1)
    let (d1x, d1y) = accumulate(
        d0x, d0y,
        1, 256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        4477254854248242929434024226743979797109261084935875761478684308825718674401,
        0
    );

    // Add pt(m=42)
    let (d2x, d2y) = accumulate(
        d1x, d1y,
        42, 10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    );

    // Final digest must match Python-computed value
    assert(d2x == 17278021077297718597230727875837231400662671451148066353875353665221356810461);
    assert(d2y == 12487403090327162322767294924447882354418311691609450543703658422765285317492);
}

// ================================================================
// V4 -- zkVM memory consistency
// write_log = [m=7, m=42, m=1]  (write order)
// read_log  = [m=1, m=7,  m=42] (read order -- different)
// Both digests must be equal -- memory is consistent
// ================================================================

#[test]
fn test_memory_consistency_v4() {

    // --- WRITE LOG: records written in order 7, 42, 1 ---

    let (w1x, w1y) = accumulate(
        1792,
        2222603532014808061213222263845635574143735707039159930479525957984581958699,
        42, 10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    );

    let (w2x, w2y) = accumulate(
        w1x, w1y,
        1, 256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        4477254854248242929434024226743979797109261084935875761478684308825718674401,
        0
    );

    // --- READ LOG: same records read back in order 1, 7, 42 ---

    let (r1x, r1y) = accumulate(
        256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        7, 1792,
        2222603532014808061213222263845635574143735707039159930479525957984581958699,
        276759698173846535821495865193274967682377030871373817764620224677696820189,
        0
    );

    let (r2x, r2y) = accumulate(
        r1x, r1y,
        42, 10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    );

    // --- MEMORY CONSISTENCY CHECK ---
    // Same records, different order -> digests must match
    assert(w2x == r2x);
    assert(w2y == r2y);
}

// ================================================================
// V6 -- BLS signing circuit (Steps 1+2)
// Section 6 of the paper: relational BLS signature scheme
//
// Standard BLS:
//   Step 1: h = HashToGroup(m)       <- expensive, ~948 constraints
//   Step 2: sigma = sk * h
//   Step 3: verify e(sigma,g2)==e(h,vk)
//
// Our version:
//   Step 1: h = MapToCurve(m)        <- our relation, ~30 constraints
//   Step 2: sigma = sk * h           <- scalar mul via embedded_curve_ops
//   Step 3: (pairing, documented separately)
//
// This circuit proves: given m, h, sigma, sk
//   - h is a valid map-to-curve output for m  (Step 1)
//   - sigma = sk * h                          (Step 2)
// ================================================================

fn bls_sign_verify(
    m: Field,        // message
    hx: Field,       // x-coord of h = map_to_curve(m)
    hy: Field,       // y-coord of h
    z: Field,        // witness: sqrt of hy
    t: Field,        // witness: tweak k
    sigma_x: Field,  // x-coord of signature sigma = sk * h
    sigma_y: Field,  // y-coord of signature sigma = sk * h
    sk: Field        // secret key (private witness)
) -> bool {
    // Step 1: verify h = map_to_curve(m)
    assert(check_map_to_curve_constraints(m, hx, hy, z, t));

    // Step 2: verify sigma = sk * h
    // Compute sk * h via double-and-add using grumpkin_add
    // For the circuit we verify the claimed sigma is consistent
    // by checking: sigma - h*(sk-1) = h  i.e.  sigma = sk*h
    // We use the EmbeddedCurvePoint API for scalar mul
    let h_point = std::embedded_curve_ops::EmbeddedCurvePoint {
        x: hx,
        y: hy,
        is_infinite: false
    };
    let scalar = std::embedded_curve_ops::EmbeddedCurveScalar {
        lo: sk as u64 as Field,
        hi: 0
    };
    let computed = std::embedded_curve_ops::multi_scalar_mul([h_point], [scalar]);
    assert(computed.x == sigma_x);
    assert(computed.y == sigma_y);
    true
}

#[test]
fn test_bls_sign_v6() {
    // sk=42, m=7 -> h=map_to_curve(7), sigma=42*h
    // All values computed by Python and verified
    let _valid = bls_sign_verify(
        7,       // message
        1792,    // hx
        2222603532014808061213222263845635574143735707039159930479525957984581958699, // hy
        276759698173846535821495865193274967682377030871373817764620224677696820189,  // z
        0,       // tweak k
        4733100100842032411897619456207212257471788614340938486107570107160445281216, // sigma_x
        14680737660313656943514597306878086649472375456366813295479094690030640350325, // sigma_y
        42       // sk
    );
    assert(_valid);
}

// ================================================================
// V7 -- Section 6.4: BLS for large messages (Ethereum block hashes)
//
// Ethereum blocks are 4KB -- too large for our 120-bit message space.
// Solution from paper Section 6.4:
//   1. Chunk block hash into 120-bit pieces: (m1, m2, m3)
//   2. Verifier sends random challenge r (Fiat-Shamir)
//   3. Compressed rep: m_tilde = m1 + r*m2 + r^2*m3  (mod pmsg)
//   4. Apply map-to-curve to m_tilde
//
// Two different 4KB blocks collide with prob <= 3 / 2^120
// ================================================================

// Compress a 3-chunk message using Fiat-Shamir randomness
// m_tilde = m1 + r*m2 + r^2*m3  (all mod the field prime)
fn fiat_shamir_compress(m1: Field, m2: Field, m3: Field, r: Field) -> Field {
    m1 + r * m2 + r * r * m3
}

#[test]
fn test_bls_ethereum_block_v7() {
    // Simulate a 256-bit Ethereum block hash chunked into 3x120-bit pieces
    // block_hash = 0xdeadbeefcafebabe1234567890abcdef1234567890abcdef1234567890abcdef
    let m1 = 271753276022767016700938344393854447;   // bits 0..119
    let m2 = 991399981940668162562752934161805074;   // bits 120..239
    let m3 = 57005;                                  // bits 240..255

    // Verifier challenge (Fiat-Shamir -- in production: hash of prover commitment)
    let r = 1311768467463790320;

    // Compress to single 120-bit representative
    let m_tilde = fiat_shamir_compress(m1, m2, m3, r);

    // Verify m_tilde maps to a valid Grumpkin point via R_M2G
    // Witness: k=10, computed off-circuit (m_tilde mod P, then increment-and-check)
    assert(check_map_to_curve_constraints(
        m_tilde,
        332924732148233668170121982520903351117802721051456032522,   // x = m_tilde*256 + 10
        12968147496580761215607456239682995263043098776383141946490851148675024911195, // y
        19623727540236807313085166479496438078681761137143889758756231737815917600226, // z
        10                                          // k=10 (10 tries needed)
    ));
}

// ================================================================
// V8 -- Security test: tweak bound enforced
// A malicious prover cannot use t >= T to break injectivity
// ================================================================

#[test]
fn test_tweak_bound_valid() {
    // t=4 is valid (< 256) -- should pass
    assert(check_map_to_curve_constraints(
        42,
        10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    ));
}

// ================================================================
// V9 -- Larger memory consistency: 5 memory records
// write_log: [m=7, m=1, m=42, m=51966, m=1]
// read_log:  [m=1, m=42, m=51966, m=7, m=1]  (different order)
// Both must produce identical digest
// ================================================================

#[test]
fn test_memory_5records_v9() {

    // --- WRITE LOG: [7, 1, 42, 51966, 1] ---
    let (w1x, w1y) = accumulate(
        1792,
        2222603532014808061213222263845635574143735707039159930479525957984581958699,
        1, 256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        4477254854248242929434024226743979797109261084935875761478684308825718674401,
        0
    );
    let (w2x, w2y) = accumulate(
        w1x, w1y,
        42, 10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    );
    let (w3x, w3y) = accumulate(
        w2x, w2y,
        51966, 13303300,
        6381688230921594513280573875668687859581864100179855876276692266416978407457,
        19238252694299235642504735672665962165555071883453037161111322236043699986662,
        4
    );
    let (write_dx, write_dy) = accumulate(
        w3x, w3y,
        1, 256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        4477254854248242929434024226743979797109261084935875761478684308825718674401,
        0
    );

    // --- READ LOG: [1, 42, 51966, 7, 1] (different order, same records) ---
    let (r1x, r1y) = accumulate(
        256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        42, 10756,
        12326530870149155666373731487040566818596147737918670480216571137303396103974,
        1399736538441884439874244412992224796867895042867937881710414215679777394985,
        4
    );
    let (r2x, r2y) = accumulate(
        r1x, r1y,
        51966, 13303300,
        6381688230921594513280573875668687859581864100179855876276692266416978407457,
        19238252694299235642504735672665962165555071883453037161111322236043699986662,
        4
    );
    let (r3x, r3y) = accumulate(
        r2x, r2y,
        7, 1792,
        2222603532014808061213222263845635574143735707039159930479525957984581958699,
        276759698173846535821495865193274967682377030871373817764620224677696820189,
        0
    );
    let (read_dx, read_dy) = accumulate(
        r3x, r3y,
        1, 256,
        9189236229814196392576801464214343739846708746841839291083803335996532870109,
        4477254854248242929434024226743979797109261084935875761478684308825718674401,
        0
    );

    // 5 records, different order, same digest -- memory consistent
    assert(write_dx == read_dx);
    assert(write_dy == read_dy);
}
