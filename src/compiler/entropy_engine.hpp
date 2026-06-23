#ifndef GUILTYATOMEIS_ENGINE_H
#define GUILTYATOMEIS_ENGINE_H

#include <chrono>
#include <cstdint>
#include <string>
#include <fstream>
#include <cstdlib>
#include <algorithm>
#include <cctype>

#if defined(_MSC_VER)
#  include <intrin.h>
#else
#  include <immintrin.h>
#endif

#ifdef __linux__
#  include <sys/ptrace.h>
#  include <unistd.h>
#endif

#ifdef _WIN32
#  include <windows.h>
#endif

struct AutonomousMalbolge
{
    uint64_t register_a;
    uint64_t weights[4];
    uint64_t engine_checksum = 0;
    uint64_t accumulated_sin = 0;
    uint32_t integrity_state = 0;

    void decoy_loop()
    {
        volatile uint64_t x = 0x5A5A5A5A5A5A5A5AULL;
        while (true) {
            x = (x ^ 0x9E3779B97F4A7C15ULL) + 1;
            x = (x << 13) | (x >> 51);
        }
    }

#ifdef __linux__
    bool check_ptrace()
    {
        if (ptrace(PTRACE_TRACEME, 0, 1, 0) < 0) {
            return true;
        }
        return false;
    }

    bool check_tracerpid()
    {
        std::ifstream status("/proc/self/status");
        std::string line;
        while (std::getline(status, line)) {
            if (line.rfind("TracerPid:", 0) == 0) {
                std::string pid_str = line.substr(10);
                size_t first = pid_str.find_first_not_of(" \t");
                if (first != std::string::npos) {
                    size_t last = pid_str.find_last_not_of(" \t\r\n");
                    std::string pid = pid_str.substr(first, (last - first + 1));
                    if (pid != "0") {
                        std::ifstream comm_file("/proc/" + pid + "/comm");
                        std::string comm;
                        if (comm_file >> comm) {
                            for (auto& c : comm) c = (char)std::tolower((unsigned char)c);
                            if (comm.find("gdb") != std::string::npos ||
                                comm.find("strace") != std::string::npos ||
                                comm.find("ltrace") != std::string::npos ||
                                comm.find("lldb") != std::string::npos ||
                                comm.find("valgrind") != std::string::npos) {
                                return true;
                            }
                        }
                    }
                }
            }
        }
        return false;
    }

    bool check_wchan()
    {
        std::ifstream wchan("/proc/self/wchan");
        std::string val;
        if (wchan >> val) {
            if (val.find("ptrace") != std::string::npos || val.find("t_stop") != std::string::npos) {
                return true;
            }
        }
        return false;
    }

    bool check_preload()
    {
        return std::getenv("LD_PRELOAD") != nullptr;
    }

    bool check_maps()
    {
        std::ifstream maps("/proc/self/maps");
        std::string line;
        while (std::getline(maps, line)) {
            if (line.find("frida") != std::string::npos || 
                line.find("jeb") != std::string::npos || 
                line.find("ida") != std::string::npos || 
                line.find("gdb") != std::string::npos) {
                return true;
            }
        }
        return false;
    }
#endif

#ifdef _WIN32
    bool check_win_debugger()
    {
        if (IsDebuggerPresent()) return true;
        BOOL isRemote = FALSE;
        if (CheckRemoteDebuggerPresent(GetCurrentProcess(), &isRemote) && isRemote) return true;
        
        // PEB Check
        #ifdef _WIN64
        unsigned char *peb = (unsigned char *)__readgsqword(0x60);
        #else
        unsigned char *peb = (unsigned char *)__readfsdword(0x30);
        #endif
        if (peb && peb[2] != 0) return true;
        
        // Hide Thread From Debugger
        HMODULE hNtDll = GetModuleHandleA("ntdll.dll");
        if (hNtDll) {
            typedef long (__stdcall *pfnNtSetInformationThread)(void*, unsigned long, void*, unsigned long);
            pfnNtSetInformationThread NtSetInformationThread = (pfnNtSetInformationThread)GetProcAddress(hNtDll, "NtSetInformationThread");
            if (NtSetInformationThread) {
                NtSetInformationThread((void*)-2, 0x11, nullptr, 0);
            }
        }
        return false;
    }
#endif

    bool check_timing()
    {
        auto start = std::chrono::high_resolution_clock::now();
        volatile int sum = 0;
        for (int i = 0; i < 1000; ++i) {
            sum += i;
        }
        auto end = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double, std::micro> diff = end - start;
        if (diff.count() > 5000.0) {
            return true;
        }
        return false;
    }

    bool check_env_vars()
    {
        const char* suspicious_vars[] = {
            "FRIDA_AUTHORITY", "IDA_LICENSE", "GHIDRA_DIR", "JEB_HOME",
            "_INTELLIJ_FORCE_SET_PHANTOM_REFS", "METASPLOIT_PATH"
        };
        for (const auto& var : suspicious_vars) {
            if (std::getenv(var) != nullptr) return true;
        }
        return false;
    }

    bool detect_env()
    {
        if (check_timing()) return true;
        if (check_env_vars()) return true;
#ifdef __linux__
        if (check_ptrace()) return true;
        if (check_tracerpid()) return true;
        if (check_wchan()) return true;
        if (check_preload()) return true;
        if (check_maps()) return true;
#endif
#ifdef _WIN32
        if (check_win_debugger()) return true;
#endif
        return false;
    }

    void init_autonomous()
    {
        if (detect_env()) {
            decoy_loop();
        }
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
        uint64_t lhs = (sin ^ integrity) + (sin & integrity);
        uint64_t rhs = sin + integrity;
        if (lhs != rhs || integrity != engine_checksum) return false;
        
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
        if (detect_env()) return false;
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
