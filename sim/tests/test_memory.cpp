#include "Vsim_mem.h"
#include "memory.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const std::string &message) {
  if (!condition) {
    throw std::runtime_error("Assertion failed: " + message);
  }
}

void write_file(const std::filesystem::path &path, const std::string &content) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream out(path);
  if (!out.is_open()) {
    throw std::runtime_error("failed to create fixture file: " + path.string());
  }
  out << content;
}

// -----------------------------------------------------------------------------
// Test 1: HEX Image Loading and Diagnostics
// -----------------------------------------------------------------------------
void test_hex_loading(const std::filesystem::path &fixture_dir) {
  std::cout << "[test_memory] Running HEX loader tests..." << std::endl;

  // 1.1 Non-existent file
  {
    std::string error;
    require(!dc_sim::load_hex_image(
                (fixture_dir / "nonexistent.hex").string(), &error),
            "loader should fail on non-existent file");
    require(error.find("unable to open image") != std::string::npos,
            "error diagnostic mismatch for non-existent file: " + error);
  }

  // 1.2 Empty file
  {
    const auto p = fixture_dir / "empty.hex";
    write_file(p, "   \n# Just comments\n  \n");
    std::string error;
    require(!dc_sim::load_hex_image(p.string(), &error),
            "loader should fail on empty image");
    require(error.find("image contains no instruction words") !=
                std::string::npos,
            "error diagnostic mismatch for empty file: " + error);
  }

  // 1.3 Bad length: 4 hex digits instead of 8
  {
    const auto p = fixture_dir / "short_word.hex";
    write_file(p, "00100093\n0402\n00008067\n");
    std::string error;
    require(!dc_sim::load_hex_image(p.string(), &error),
            "loader should fail on 4-digit hex word");
    require(error.find("line 2") != std::string::npos ||
                error.find(":2:") != std::string::npos,
            "error should point to line 2: " + error);
    require(error.find("exactly 8 hex digits") != std::string::npos,
            "error diagnostic mismatch for word length: " + error);
  }

  // 1.4 Non-hex character
  {
    const auto p = fixture_dir / "non_hex.hex";
    write_file(p, "00100093\n002081bz\n");
    std::string error;
    require(!dc_sim::load_hex_image(p.string(), &error),
            "loader should fail on non-hex character");
    require(error.find(":2:") != std::string::npos,
            "error should point to line 2: " + error);
    require(error.find("non-hex character") != std::string::npos,
            "error diagnostic mismatch for non-hex character: " + error);
  }

  // 1.5 Capacity overflow: 257 words (limit is 256)
  {
    const auto p = fixture_dir / "overflow.hex";
    std::ostringstream oss;
    for (int i = 0; i < 257; ++i) {
      oss << "00000013  # nop " << i << "\n";
    }
    write_file(p, oss.str());
    std::string error;
    require(!dc_sim::load_hex_image(p.string(), &error),
            "loader should fail on > 256 words");
    require(error.find(":257:") != std::string::npos,
            "error should point to line 257: " + error);
    require(error.find("exceeds the 256-word") != std::string::npos,
            "error diagnostic mismatch for capacity overflow: " + error);
  }

  // 1.6 Valid 8-char hex with mixed case, comments, spaces
  {
    const auto p = fixture_dir / "valid_smoke.hex";
    write_file(p,
               "# RV32E v0.2 smoke program\n"
               "00100093  # addi x1, x0, 1\n"
               "  \n"
               "002081B3  # add x3, x1, x2 (uppercase hex)\n"
               "00008067  # jalr x0, 0(x1)\n");
    std::string error;
    require(dc_sim::load_hex_image(p.string(), &error),
            "loader should succeed on valid hex: " + error);
    require(dc_sim::image_word_count() == 3, "word count should be 3");
    require(dc_sim::read_irom_word(0) == 0x00100093, "word 0 mismatch");
    require(dc_sim::read_irom_word(1) == 0x002081b3, "word 1 mismatch");
    require(dc_sim::read_irom_word(2) == 0x00008067, "word 2 mismatch");
  }

  std::cout << "[test_memory] HEX loader tests: PASS" << std::endl;
}

// -----------------------------------------------------------------------------
// Test 2: Hardware/Simulation Protocol Verification with sim_mem
// -----------------------------------------------------------------------------
class MemoryTestbench {
 public:
  MemoryTestbench()
      : context_(std::make_unique<VerilatedContext>()),
        dut_(std::make_unique<Vsim_mem>(context_.get())) {
    dut_->clk = 0;
    dut_->rst = 1;
    dut_->imem_req_valid = 0;
    dut_->imem_req_addr = 0;
    dut_->imem_rsp_ready = 0;
    dut_->dmem_req_valid = 0;
    dut_->dmem_req_addr = 0;
    dut_->dmem_req_write = 0;
    dut_->dmem_req_size = 0;
    dut_->dmem_req_wdata = 0;
    dut_->dmem_req_wstrb = 0;
    dut_->dmem_rsp_ready = 0;
    dut_->eval();
  }

  void tick() {
    context_->timeInc(1);
    dut_->clk = 1;
    dut_->eval();
    context_->timeInc(1);
    dut_->clk = 0;
    dut_->eval();
  }

  void reset() {
    dut_->rst = 1;
    dut_->imem_req_valid = 0;
    dut_->dmem_req_valid = 0;
    dut_->dmem_rsp_ready = 0;
    for (int i = 0; i < 2; ++i) {
      tick();
    }
    dut_->rst = 0;
    dut_->eval();
  }

  Vsim_mem *dut() { return dut_.get(); }

 private:
  std::unique_ptr<VerilatedContext> context_;
  std::unique_ptr<Vsim_mem> dut_;
};

void test_irom_protocol() {
  std::cout << "[test_memory] Running IROM protocol tests..." << std::endl;
  MemoryTestbench tb;
  tb.reset();

  // Load known words into IROM
  dc_sim::reset_memory();
  // Manually put words into IROM via sim_irom_read mock
  // Or write a small HEX image
  // We know dc_sim::read_irom_word is backed by irom_storage
  // Let's test using DPI calls and ports
  std::string error;
  const std::string temp_hex = "build/test-fixtures/memory/irom_test.hex";
  write_file(temp_hex,
             "01234567\n"
             "89abcdef\n"
             "deadbeef\n");
  require(dc_sim::load_hex_image(temp_hex, &error), "load temp hex failed");

  auto *dut = tb.dut();

  // 2.1 Same-cycle asynchronous read of word 0
  dut->imem_req_valid = 1;
  dut->imem_req_addr = 0x00000000;
  dut->eval();
  require(dut->imem_req_ready == 1, "IROM word 0 req_ready should be 1");
  require(dut->imem_rsp_valid == 1, "IROM word 0 rsp_valid should be 1");
  require(dut->imem_rsp_error == 0, "IROM word 0 rsp_error should be 0");
  require(dut->imem_rsp_rdata == 0x01234567,
          "IROM word 0 rdata mismatch: got " + std::to_string(dut->imem_rsp_rdata));

  // 2.2 Same-cycle read of word 1
  dut->imem_req_addr = 0x00000004;
  dut->eval();
  require(dut->imem_rsp_rdata == 0x89abcdef, "IROM word 1 rdata mismatch");

  // 2.3 Same-cycle read of word 2
  dut->imem_req_addr = 0x00000008;
  dut->eval();
  require(dut->imem_rsp_rdata == 0xdeadbeef, "IROM word 2 rdata mismatch");

  // 2.4 Out of bounds read: >= 1024 (0x400)
  dut->imem_req_addr = 0x00000400;
  dut->eval();
  require(dut->imem_req_ready == 1, "IROM OOB req_ready should be 1");
  require(dut->imem_rsp_valid == 1, "IROM OOB rsp_valid should be 1");
  require(dut->imem_rsp_error == 1, "IROM OOB rsp_error should be 1");
  require(dut->imem_rsp_rdata == 0, "IROM OOB rdata should be 0");

  // 2.5 Unaligned instruction address
  dut->imem_req_addr = 0x00000002;
  dut->eval();
  require(dut->imem_rsp_error == 1, "IROM unaligned addr should produce error");

  // 2.6 Deasserted valid
  dut->imem_req_valid = 0;
  dut->eval();
  require(dut->imem_req_ready == 0, "IROM req_ready should be 0 when valid=0");
  require(dut->imem_rsp_valid == 0, "IROM rsp_valid should be 0 when valid=0");

  std::cout << "[test_memory] IROM protocol tests: PASS" << std::endl;
}

void test_dram_read_write_protocol() {
  std::cout << "[test_memory] Running DRAM read/write protocol tests..."
            << std::endl;
  MemoryTestbench tb;
  tb.reset();
  auto *dut = tb.dut();
  dc_sim::reset_memory();

  // 3.1 Synchronous 1-cycle latency write
  // Address 0x1000 (word 0 of DRAM), data 0xaabbccdd, wstrb 4'b1111 (SW)
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001000;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;  // word
  dut->dmem_req_wdata = 0xaabbccdd;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 1;
  dut->eval();

  require(dut->dmem_req_ready == 1, "DRAM req_ready should be 1 in cycle N");
  require(dut->dmem_rsp_valid == 0,
          "DRAM rsp_valid should still be 0 in cycle N");

  // Clock edge N -> N+1
  tb.tick();

  // Cycle N+1: response is valid
  require(dut->dmem_rsp_valid == 1, "DRAM rsp_valid should be 1 in cycle N+1");
  require(dut->dmem_rsp_error == 0, "DRAM rsp_error should be 0 in cycle N+1");

  // Deassert request
  dut->dmem_req_valid = 0;

  // Advance clock: store writes on handshake edge (since rsp_ready == 1)
  tb.tick();

  require(dut->dmem_rsp_valid == 0,
          "DRAM rsp_valid should clear after handshake");
  require(dc_sim::read_dram_word(0) == 0xaabbccdd,
          "DRAM word 0 was not written correctly");

  // 3.2 Synchronous 1-cycle latency read
  // Read back from 0x1000
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001000;
  dut->dmem_req_write = 0;
  dut->dmem_req_size = 2;
  dut->dmem_req_wdata = 0;
  dut->dmem_req_wstrb = 0;
  dut->dmem_rsp_ready = 1;
  dut->eval();

  require(dut->dmem_req_ready == 1, "DRAM read req_ready should be 1");
  tb.tick();

  dut->dmem_req_valid = 0;
  require(dut->dmem_rsp_valid == 1, "DRAM read rsp_valid should be 1");
  require(dut->dmem_rsp_error == 0, "DRAM read rsp_error should be 0");
  require(dut->dmem_rsp_rdata == 0xaabbccdd, "DRAM read rdata mismatch");

  tb.tick();
  require(dut->dmem_rsp_valid == 0, "DRAM read response finished");

  // 3.3 Byte strobes (SB) verification
  // Current word 0 is 0xaabbccdd (little-endian bytes: dd, cc, bb, aa)
  // Modify byte 0 (lane 0) to 0x11
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001000;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 0;  // byte
  dut->dmem_req_wdata = 0x00000011;
  dut->dmem_req_wstrb = 0x01;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  tb.tick();
  require(dc_sim::read_dram_word(0) == 0xaabbcc11,
          "wstrb=0001 byte 0 update mismatch");

  // Modify byte 2 (lane 2) to 0x22
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001002;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 0;
  dut->dmem_req_wdata = 0x00220000;
  dut->dmem_req_wstrb = 0x04;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  tb.tick();
  require(dc_sim::read_dram_word(0) == 0xaa22cc11,
          "wstrb=0100 byte 2 update mismatch");

  std::cout << "[test_memory] DRAM read/write protocol tests: PASS"
            << std::endl;
}

void test_dram_read_first_and_backpressure() {
  std::cout << "[test_memory] Running DRAM read-first & backpressure tests..."
            << std::endl;
  MemoryTestbench tb;
  tb.reset();
  auto *dut = tb.dut();
  dc_sim::reset_memory();

  // Set initial content at 0x1004 (word 1) = 0x12345678
  dc_sim::write_dram_byte(0x1004, 0x78);
  dc_sim::write_dram_byte(0x1005, 0x56);
  dc_sim::write_dram_byte(0x1006, 0x34);
  dc_sim::write_dram_byte(0x1007, 0x12);
  require(dc_sim::read_dram_word(1) == 0x12345678, "initial setup mismatch");

  // 4.1 Read-first: issue write to 0x1004 with new data 0x99999999
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001004;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;
  dut->dmem_req_wdata = 0x99999999;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  // In cycle N+1, rsp_rdata contains the sampled read-first old value
  require(dut->dmem_rsp_valid == 1, "rsp_valid should be 1");
  require(dut->dmem_rsp_rdata == 0x12345678,
          "read-first old data should be returned on write cycle");

  tb.tick();
  // Now store has committed
  require(dc_sim::read_dram_word(1) == 0x99999999,
          "new data should be written after handshake");

  // 4.2 Backpressure: keep dmem_rsp_ready = 0 for 3 cycles
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001008;  // word 2
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;
  dut->dmem_req_wdata = 0x55555555;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 0;  // Backpressure!
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  // Verify response valid and backpressure hold for 3 consecutive cycles
  for (int cycle = 0; cycle < 3; ++cycle) {
    dut->eval();
    require(dut->dmem_rsp_valid == 1,
            "rsp_valid must stay high during backpressure");
    require(dut->dmem_rsp_error == 0,
            "rsp_error must stay 0 during backpressure");
    require(dut->dmem_req_ready == 0,
            "req_ready must be 0 while response holds");
    require(dc_sim::read_dram_word(2) == 0,
            "store must NOT take effect until response handshake!");
    tb.tick();
  }

  // Now release backpressure: dmem_rsp_ready = 1
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  // Now store has committed!
  require(dut->dmem_rsp_valid == 0, "rsp_valid should clear after handshake");
  require(dc_sim::read_dram_word(2) == 0x55555555,
          "store should commit on handshake edge");

  std::cout << "[test_memory] DRAM read-first & backpressure tests: PASS"
            << std::endl;
}

void test_tohost_protocol() {
  std::cout << "[test_memory] Running tohost protocol tests..." << std::endl;
  MemoryTestbench tb;
  tb.reset();
  auto *dut = tb.dut();
  dc_sim::reset_memory();

  // 5.1 Legal SW to tohost (0xfffffff0), guest exit code 0 (success)
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0xfffffff0;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;  // word
  dut->dmem_req_wdata = 0x00000000;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  require(dut->dmem_req_ready == 1, "tohost SW should be accepted");

  tb.tick();
  dut->dmem_req_valid = 0;
  require(dut->dmem_rsp_valid == 1, "tohost response should be valid");
  require(dut->dmem_rsp_error == 0, "tohost legal SW should have error=0");
  require(dut->tohost_exit == 0, "tohost_exit must not assert before handshake");

  tb.tick();
  require(dut->tohost_exit == 1, "tohost_exit must assert on handshake");
  require(dut->guest_exit_code == 0, "guest exit code mismatch");

  // 5.2 Legal SW to tohost with non-zero exit code (failure code 42)
  tb.reset();
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0xfffffff0;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;
  dut->dmem_req_wdata = 42;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  tb.tick();
  require(dut->tohost_exit == 1, "tohost_exit should assert");
  require(dut->guest_exit_code == 42, "guest exit code should be 42");

  // 5.3 Illegal tohost accesses
  tb.reset();
  // 5.3a: Load from tohost (illegal)
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0xfffffff0;
  dut->dmem_req_write = 0;  // load!
  dut->dmem_req_size = 2;
  dut->dmem_req_wstrb = 0;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  require(dut->dmem_rsp_valid == 1, "response should be valid");
  require(dut->dmem_rsp_error == 1, "load from tohost must return error=1");
  tb.tick();
  require(dut->tohost_exit == 0, "tohost_exit must NOT assert on load");

  // 5.3b: Store byte to tohost (illegal)
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0xfffffff0;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 0;  // byte!
  dut->dmem_req_wdata = 0x00000001;
  dut->dmem_req_wstrb = 0x01;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  require(dut->dmem_rsp_valid == 1, "response should be valid");
  require(dut->dmem_rsp_error == 1, "SB to tohost must return error=1");
  tb.tick();
  require(dut->tohost_exit == 0, "tohost_exit must NOT assert on SB");

  std::cout << "[test_memory] tohost protocol tests: PASS" << std::endl;
}

void test_unmapped_and_reset_protocol() {
  std::cout << "[test_memory] Running unmapped & reset protocol tests..."
            << std::endl;
  MemoryTestbench tb;
  tb.reset();
  auto *dut = tb.dut();
  dc_sim::reset_memory();

  // 6.1 Unmapped address in hole: 0x00000800
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00000800;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;
  dut->dmem_req_wdata = 0xdeadbeef;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  require(dut->dmem_rsp_valid == 1, "unmapped access response valid");
  require(dut->dmem_rsp_error == 1, "unmapped access must return error=1");
  tb.tick();

  // 6.2 Unmapped address past DRAM: 0x00002000
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00002000;
  dut->dmem_req_write = 0;
  dut->dmem_rsp_ready = 1;
  dut->eval();
  tb.tick();

  dut->dmem_req_valid = 0;
  require(dut->dmem_rsp_error == 1, "unmapped read must return error=1");
  tb.tick();

  // 6.3 Reset flushes in-flight transaction
  dut->dmem_req_valid = 1;
  dut->dmem_req_addr = 0x00001000;
  dut->dmem_req_write = 1;
  dut->dmem_req_size = 2;
  dut->dmem_req_wdata = 0x77777777;
  dut->dmem_req_wstrb = 0x0f;
  dut->dmem_rsp_ready = 0;
  dut->eval();
  tb.tick();

  // In-flight response is pending: assert reset
  dut->dmem_req_valid = 0;
  dut->rst = 1;
  dut->eval();
  tb.tick();

  // In reset: response valid must be cleared immediately
  require(dut->dmem_rsp_valid == 0,
          "reset must clear in-flight dmem_rsp_valid");
  require(dc_sim::read_dram_word(0) != 0x77777777,
          "reset must cancel pending store write");

  dut->rst = 0;
  dut->eval();
  require(dut->dmem_req_ready == 1, "ready should restore after reset");

  std::cout << "[test_memory] unmapped & reset protocol tests: PASS"
            << std::endl;
}

}  // namespace

int main(int argc, char **argv) {
  const std::filesystem::path fixture_dir =
      argc > 1 ? argv[1] : "build/test-fixtures/memory";

  try {
    test_hex_loading(fixture_dir);
    test_irom_protocol();
    test_dram_read_write_protocol();
    test_dram_read_first_and_backpressure();
    test_tohost_protocol();
    test_unmapped_and_reset_protocol();
    std::cout << "\nALL MEMORY TESTS PASSED!" << std::endl;
    return 0;
  } catch (const std::exception &ex) {
    std::cerr << "test_memory FAILED: " << ex.what() << std::endl;
    return 1;
  }
}
