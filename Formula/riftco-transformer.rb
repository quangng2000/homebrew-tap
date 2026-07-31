class RiftcoTransformer < Formula
  desc "Auditable transformer framework with C/C++ APIs and training CLI"
  homepage "https://github.com/quangng2000/riftco-transformer"
  url "https://github.com/quangng2000/riftco-transformer/releases/download/v0.2.0/riftco_transformer-0.2.0.tar.gz"
  sha256 "cd6e964098ba637320c8a6a6a4d42d5dcd60ecf1b8460fc79d047fb4cd7fb453"
  license "Apache-2.0"
  head "https://github.com/quangng2000/riftco-transformer.git", branch: "main"

  depends_on "cmake" => [:build, :test]

  def install
    args = %W[
      -DRIFTCO_TRANSFORMER_BUILD_CLI=ON
      -DRIFTCO_TRANSFORMER_BUILD_PYTHON_WHEEL=OFF
      -DRIFTCO_TRANSFORMER_BUILD_TESTS=OFF
      -DRIFTCO_TRANSFORMER_ENABLE_INSTALL=ON
      -DRIFTCO_TRANSFORMER_ENABLE_METAL=#{OS.mac? ? "ON" : "OFF"}
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  def caveats
    <<~EOS
      The training CLI needs an explicit configuration after installation:

        riftco-transformer --config /path/to/config.conf

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
      "#{bin}/riftco-transformer --config #{config} --steps 1 " \
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
      #include "riftco_transformer/c_api.h"
      #include <stdint.h>
      #include <stdlib.h>

      int main(void) {
        int32_t available = 0;
        if (rt_abi_version() != RT_ABI_VERSION ||
            rt_backend_is_available(RT_BACKEND_CPU, &available) != RT_STATUS_OK ||
            available == 0) {
          return EXIT_FAILURE;
        }
        return EXIT_SUCCESS;
      }
    C
    (testpath/"CMakeLists.txt").write <<~CMAKE
      cmake_minimum_required(VERSION 3.24)
      project(riftco_transformer_formula_test LANGUAGES C)
      find_package(riftco_transformer 0.2 CONFIG REQUIRED)
      add_executable(abi_test abi_test.c)
      target_link_libraries(abi_test PRIVATE riftco_transformer::c_api)
    CMAKE
    system "cmake", "-S", ".", "-B", "consumer-build",
           "-DCMAKE_PREFIX_PATH=#{prefix}", *std_cmake_args
    system "cmake", "--build", "consumer-build"
    system testpath/"consumer-build/abi_test"
  end
end
