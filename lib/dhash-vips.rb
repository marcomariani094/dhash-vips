require "vips"

module DHashVips

  module DHash
    extend self

    def hamming a, b
      (a ^ b).to_s(2).count "1"
    end

    def pixelate file, hash_size, kernel = nil
      image = Vips::Image.new_from_file file, access: :sequential
      if kernel
        image.resize((hash_size + 1).fdiv(image.width), vscale: hash_size.fdiv(image.height), kernel: kernel).colourspace("b-w")
      else
        image.resize((hash_size + 1).fdiv(image.width), vscale: hash_size.fdiv(image.height)                ).colourspace("b-w")
      end
    end

    def calculate file, hash_size = 8, kernel = nil
      image = pixelate file, hash_size, kernel

      image.cast("int").conv([[1, -1]]).crop(1, 0, hash_size, hash_size).>(0)./(255).cast("uchar").to_a.join.to_i(2)
    end

    def pixelate_by_url url, hash_size, kernel = nil
      require "open-uri"
      buffer = open(url, &:read)
      image = Vips::Image.new_from_buffer(buffer, "")

      if kernel
        image.resize((hash_size + 1).fdiv(image.width), vscale: hash_size.fdiv(image.height), kernel: kernel).colourspace("b-w")
      else
        image.resize((hash_size + 1).fdiv(image.width), vscale: hash_size.fdiv(image.height)                ).colourspace("b-w")
      end
    end

    def calculate_by_url url, hash_size = 8, kernel = nil
      image = pixelate_by_url url, hash_size, kernel

      # To remove alpha channel if presents
      image = image.flatten if image.bands > 1

      image.cast("int").conv([[1, -1]]).crop(1, 0, hash_size, hash_size).>(0)./(255).cast("uchar").to_a.join.to_i(2)
    end

  end

  module IDHash
    extend self

    def distance3_ruby a, b
      ((a ^ b) & (a | b) >> 128).to_s(2).count "1"
    end
    begin
      require_relative "../idhash.#{Gem::Platform.local.os == "darwin" ? "bundle" : "o"}"
    rescue LoadError
      alias_method :distance3, :distance3_ruby
    else
      # we can't just do `defined? Bignum` because it's defined but deprecated (some internal CONST_DEPRECATED flag)
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.4")
        def distance3 a, b
          if a.is_a?(Bignum) && b.is_a?(Bignum)
            distance3_c a, b
          else
            distance3_ruby a, b
          end
        end
      else
        # https://github.com/ruby/ruby/commit/de2f7416d2deb4166d78638a41037cb550d64484#diff-16b196bc6bfe8fba63951420f843cfb4R10
        require "rbconfig/sizeof"
        FIXNUM_MAX = (1 << (8 * RbConfig::SIZEOF["long"] - 2)) - 1
        def distance3 a, b
          if a > FIXNUM_MAX && b > FIXNUM_MAX
            distance3_c a, b
          else
            distance3_ruby a, b
          end
        end
      end
    end
    def distance a, b
      size_a, size_b = [a, b].map do |x|
        # TODO write a test about possible hash sizes
        #      they were 32 and 128, 124, 120 for MRI 2.0
        #      but also 31, 30 happens for MRI 2.3
        x.size <= 32 ? 8 : 16
      end
      return distance3 a, b if [8, 8] == [size_a, size_b]
      fail "fingerprints were taken with different `power` param: #{size_a} and #{size_b}" if size_a != size_b
      ((a ^ b) & (a | b) >> 2 * size_a * size_a).to_s(2).count "1"
    end

    @@median = lambda do |array|
      h = array.size / 2
      return array[h] if array[h] != array[h - 1]
      right = array.dup
      left = right.shift h
      right.shift if right.size > left.size
      return right.first if left.last != right.first
      return right.uniq[1] if left.count(left.last) > right.count(right.first)
      left.last
    end
    fail unless 2 == @@median[[1, 2, 2, 2, 2, 2, 3]]
    fail unless 3 == @@median[[1, 2, 2, 2, 2, 3, 3]]
    fail unless 3 == @@median[[1, 1, 2, 2, 3, 3, 3]]
    fail unless 2 == @@median[[1, 1, 1, 2, 3, 3, 3]]
    fail unless 2 == @@median[[1, 1, 2, 2, 2, 2, 3]]
    fail unless 2 == @@median[[1, 2, 2, 2, 2, 3]]
    fail unless 3 == @@median[[1, 2, 2, 3, 3, 3]]
    fail unless 1 == @@median[[1, 1, 1]]
    fail unless 1 == @@median[[1, 1]]

    def fingerprint filename, power = 3
      size = 2 ** power
      image = Vips::Image.new_from_file filename, access: :sequential
      fingerprint_by_image(image, size)
    end

    def fingerprint_by_url url, power = 3
      size = 2 ** power

      require "open-uri"
      buffer = open(url, &:read)
      image = Vips::Image.new_from_buffer(buffer, "")

      fingerprint_by_image(image, size)
    end

    private

    def fingerprint_by_image(image, size)
      image = image.resize(size.fdiv(image.width), vscale: size.fdiv(image.height)).colourspace("b-w").flatten

      array = image.to_a.map &:flatten
      d1, i1, d2, i2 = [array, array.transpose].flat_map do |a|
        d = a.zip(a.rotate(1)).flat_map{ |r1, r2| r1.zip(r2).map{ |i,j| i - j } }
        m = @@median.call d.map(&:abs).sort
        [
          d.map{ |c| c     <  0 ? 1 : 0 }.join.to_i(2),
          d.map{ |c| c.abs >= m ? 1 : 0 }.join.to_i(2),
        ]
      end
      (((((i1 << size * size) + i2) << size * size) + d1) << size * size) + d2
    end

  end

end
