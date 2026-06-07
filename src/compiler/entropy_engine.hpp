#ifndef GUILTYATOMEIS_ENGINE_H
#define GUILTYATOMEIS_ENGINE_H

#include <chrono>
#include <cstdint>
#if defined(_MSC_VER)
#  include <intrin.h>
#else
#  include <immintrin.h>
#endif

struct AutonomousMalbolge
{
    uint64_t register_a;
    uint64_t weights[4];
    uint64_t engine_checksum = 0;
    uint64_t accumulated_sin = 0;
    uint32_t integrity_state = 0;

    void init_autonomous()
    {
        unsigned long long r;
        if (!_rdrand64_step(&r)) {
            auto now = std::chrono::high_resolution_clock::now().time_since_epoch().count();
            r = (uint64_t)now ^ 0x5A5A5A5A5A5A5A5AULL;
        }
        set_register(r);
    }

    void set_register(uint64_t val)
    {
        register_a = val;
        weights[0] = val ^ 0x5555555555555555ULL;
        weights[1] = (val << 32) | (val >> 32);
        weights[2] = val ^ 0xAAAAAAAAAAAAAAAAULL;
        weights[3] = ~val;
        accumulated_sin = 0;
        integrity_state = 0;
    }

    uint64_t get_register() { return register_a; }

    uint64_t generate_true_spice()
    {
        unsigned long long r;
        if (!_rdrand64_step(&r)) return std::chrono::high_resolution_clock::now().time_since_epoch().count();
        return r;
    }

    void churn(uint64_t spice)
    {
        register_a ^= spice ^ engine_checksum ^ accumulated_sin;
        register_a = (register_a << 13) | (register_a >> 51);
        register_a *= 0xBF58476D1CE4E5B9ULL;
        weights[register_a % 4] ^= register_a;
    }

    // Phase 7: Spatial Mapping (PC-Relative Encryption)
    void encrypt_fhe(int32_t data, uint64_t spice, uint64_t pc, uint64_t *out_low, uint64_t *out_high)
    {
        churn(spice ^ pc);
        uint64_t r_key = (register_a ^ pc) % 100000000ULL;
        *out_low = (r_key * 1000000000ULL) + (uint64_t)((uint32_t)data) + 10;
        *out_high = spice;
    }

    int32_t decrypt_fhe(uint64_t in_low, uint64_t in_high, uint64_t pc)
    {
        churn(in_high ^ pc);
        uint64_t r_key = (register_a ^ pc) % 100000000ULL;
        uint64_t res = in_low - (r_key * 1000000000ULL) - 10;
        return (int32_t)((uint32_t)res);
    }

    void fhe_add(uint64_t a_low, uint64_t a_high, uint64_t a_idx, 
                 uint64_t b_low, uint64_t b_high, uint64_t b_idx,
                 uint64_t out_idx, uint64_t *out_low, uint64_t *out_high)
    {
        int32_t val_a = stable_decrypt(a_low, a_high, a_idx);
        int32_t val_b = stable_decrypt(b_low, b_high, b_idx);
        stable_encrypt(val_a + val_b, out_idx, out_low, out_high);
    }

    void fhe_sub(uint64_t a_low, uint64_t a_high, uint64_t a_idx, 
                 uint64_t b_low, uint64_t b_high, uint64_t b_idx,
                 uint64_t out_idx, uint64_t *out_low, uint64_t *out_high)
    {
        int32_t val_a = stable_decrypt(a_low, a_high, a_idx);
        int32_t val_b = stable_decrypt(b_low, b_high, b_idx);
        stable_encrypt(val_a - val_b, out_idx, out_low, out_high);
    }

    // Spiral Regeneration: Opaque Absolution
    bool conduct_absolution(uint64_t sin, uint64_t integrity, uint64_t next_sin)
    {
        // 罪（エントロピー）と身体（ハッシュ）の結合検証
        uint64_t lhs = (sin ^ integrity) + (sin & integrity);
        uint64_t rhs = sin + integrity;
        if (lhs != rhs || integrity != engine_checksum) return false;
        
        // 螺旋の遷移：SIN の再同期
        accumulated_sin = next_sin;
        register_a ^= next_sin;
        return true;
    }

    void evolve_isa(uint8_t op)
    {
        register_a += (uint64_t)op;
        accumulated_sin ^= register_a;
    }

    uint64_t stable_encrypt(int32_t data, uint64_t index, uint64_t *out_low, uint64_t *out_high)
    {
        uint64_t spice = generate_true_spice();
        uint64_t r_key = (register_a ^ index ^ engine_checksum) % 100000000ULL;
        *out_low = (r_key * 1000000000ULL) + (uint64_t)((uint32_t)data) + 10;
        *out_high = spice;
        return spice;
    }

    int32_t stable_decrypt(uint64_t in_low, uint64_t in_high, uint64_t index)
    {
        uint64_t r_key = (register_a ^ index ^ engine_checksum) % 100000000ULL;
        uint64_t res = in_low - (r_key * 1000000000ULL) - 10;
        return (int32_t)((uint32_t)res);
    }

    uint32_t get_history_hash(uint64_t pc)
    {
        uint64_t h = register_a ^ pc ^ engine_checksum;
        for(int i=0; i<4; i++) h ^= weights[i];
        return (uint32_t)((h ^ (h >> 32)) & 0xFFFFFFFF);
    }

    void corrupt_history() { integrity_state = 1; register_a = 0; }
    
    bool opaque_verify() {
        uint64_t x = register_a;
        uint64_t y = weights[register_a % 4];
        return ((x | y) + (x & y) == (x + y));
    }

    uint64_t get_accumulated_sin() { return accumulated_sin; }
    void set_accumulated_sin(uint64_t s) { accumulated_sin = s; }
    void force_self_checksum(uint32_t cs) { engine_checksum = cs; }
    uint64_t get_self_checksum() { return engine_checksum; }
    uint64_t armor_id() { return engine_checksum != 0 ? 0x1337 : 0; }
    uint32_t get_dynamic_offset(uint64_t pc) { return (uint32_t)((register_a ^ pc) & 0xFF); }
};

#endif
