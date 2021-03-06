class Armadillo < Formula
  desc "C++ linear algebra library"
  homepage "https://arma.sourceforge.io/"
  url "https://downloads.sourceforge.net/project/arma/armadillo-9.100.5.tar.xz"
  sha256 "7e7dc6f1e876b8243c27a003b037559663371b42885436b1087757e652db41cd"
  revision 1

  bottle do
    cellar :any
    sha256 "a43a02fc742f5a374f12f3860060c0d093df453a609f2dc8da18b0da4b30625e" => :mojave
    sha256 "1d0bd452b03c06f6d664689908329eb12d55d1c0a5878820d9ba09d291062a44" => :high_sierra
    sha256 "c4fb7be0310d5ff307dfba1a15bc20f2134ae6549ea5a440644f0ab8ac0a4b20" => :sierra
    sha256 "f295626e515f42571de8f9d5f58722278c8319cb812cecff388b3626b652b40e" => :el_capitan
    sha256 "7a1597b71e5ebd5a810adeba81e8cb699e90e16dec6c1e426bc8c10ec431fb84" => :x86_64_linux
  end

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "arpack"
  depends_on "hdf5"
  depends_on "superlu"

  def install
    system "cmake", ".", "-DDETECT_HDF5=ON", *std_cmake_args
    system "make", "install"
  end

  test do
    (testpath/"test.cpp").write <<~EOS
      #include <iostream>
      #include <armadillo>

      int main(int argc, char** argv) {
        std::cout << arma::arma_version::as_string() << std::endl;
      }
    EOS
    system ENV.cxx, "test.cpp", "-I#{include}", "-L#{lib}", "-larmadillo", "-o", "test"
    assert_equal Utils.popen_read("./test").to_i, version.to_s.to_i
  end
end
