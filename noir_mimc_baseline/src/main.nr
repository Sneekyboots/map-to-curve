fn main(m: Field, h: Field) {
    let result = std::hash::pedersen_hash([m]);
    assert(result == h);
}
