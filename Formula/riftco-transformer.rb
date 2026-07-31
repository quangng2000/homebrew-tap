class RiftcoTransformer < Formula
  desc "Auditable transformer framework with C/C++ APIs and training CLI"
  homepage "https://github.com/quangng2000/riftco-transformer"
  url "https://github.com/quangng2000/riftco-transformer/releases/download/v0.1.0/riftco_transformer-0.1.0.tar.gz"
  sha256 "bc93ca32680183a34c719c1767b6e2f159e1a95e78dadd500477d76b688ad420"
  license "Apache-2.0"
  head "https://github.com/quangng2000/riftco-transformer.git", branch: "main"

  depends_on "cmake" => [:build, :test]

  def install
    args = %W[
      -DTRANSFORMER_LAB_BUILD_CLI=ON
      -DTRANSFORMER_LAB_BUILD_PYTHON_WHEEL=OFF
      -DTRANSFORMER_LAB_BUILD_TESTS=OFF
      -DTRANSFORMER_LAB_ENABLE_INSTALL=ON
      -DTRANSFORMER_LAB_ENABLE_METAL=#{OS.mac? ? "ON" : "OFF"}
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  def caveats
    <<~EOS
      The training CLI needs an explicit configuration after installation:

        transformer_lab --config /path/to/config.conf

      Example configuration:
      https://github.com/quangng2000/riftco-transformer/blob/v#{version}/configs/tiny.conf
    EOS
  end

  test do
    corpus = testpath/"corpus.txt"
    config = testpath/"config/tiny.conf"
    metrics = testpath/"metrics.csv"
    corpus.write "abababababababab\n"
    config.dirname.mkpath
    config.write <<~EOS
      corpus = corpus.txt
      results = results
      seed = 7
      context_size = 2
      batch_size = 1
      d_model = 4
      n_heads = 1
      n_layers = 1
      d_ff = 8
      training_steps = 1
      sample_every = 1
      sample_length = 1
      learning_rate = 0.001
      adam_beta1 = 0.9
      adam_beta2 = 0.999
      adam_epsilon = 0.00000001
      gradient_clip = 1.0
    EOS

    output = shell_output(
      "#{bin}/transformer_lab --config #{config} --steps 1 " \
      "--metrics #{metrics} --backend cpu --attention flash " \
      "--activation-checkpointing block",
    )
    assert_match(/Backend:\s+cpu/, output)
    assert_match(/Attention:\s+flash/, output)
    assert_match(/Checkpointing:\s+block/, output)
    assert_match "Training loop: complete.", output
    assert_path_exists metrics
    assert_equal 2, metrics.read.lines.length
    assert_match(/^1,/, metrics.read.lines.fetch(1))

    (testpath/"abi_test.c").write <<~C
      #include "transformer_lab/c_api.h"
      #include <stdint.h>
      #include <stdlib.h>

      int main(void) {
        int32_t available = 0;
        if (tl_abi_version() != TL_ABI_VERSION ||
            tl_backend_is_available(TL_BACKEND_CPU, &available) != TL_STATUS_OK ||
            available == 0) {
          return EXIT_FAILURE;
        }
        return EXIT_SUCCESS;
      }
    C
    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 3.24)
      project(transformer_lab_formula_test LANGUAGES C)
      find_package(transformer_lab 0.1 CONFIG REQUIRED)
      add_executable(abi_test abi_test.c)
      target_link_libraries(abi_test PRIVATE transformer_lab::c_api)
    CMAKE
    system "cmake", "-S", ".", "-B", "consumer-build",
                    "-DCMAKE_PREFIX_PATH=#{prefix}", *std_cmake_args
    system "cmake", "--build", "consumer-build"
    system testpath/"consumer-build/abi_test"
  end
end
