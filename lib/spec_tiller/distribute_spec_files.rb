require 'yaml'

module TravisBuildMatrix

  DEFAULT_NUM_BUILDS = 5

    class SpecFile
      attr_accessor :file_path, :test_duration

      def initialize(file_path, test_duration)
        @test_duration = test_duration
        @file_path = file_path
      end
    end

    class TestBucket
      attr_reader :spec_files, :total_duration

      def initialize
        @total_duration = 0.0
        @spec_files = []
      end

      def add_to_list(spec_file)
        @spec_files << spec_file
        @total_duration += spec_file.test_duration
      end
    end

    class SpecDistributor

      EXTRACT_DURATION_AND_FILE_PATH = /\s{1}\(([0-9\.]*\s).*\.\/(spec.*):/

      def initialize(travis_yml_file, profile_results, &block)
        num_buckets = travis_yml_file['num_builds'] || DEFAULT_NUM_BUILDS

        @spec_files = parse_profile_results(profile_results)
        @test_buckets = Array.new(num_buckets){ |_| TestBucket.new }
        
        distribute_tests

        TravisBuildMatrix::TravisFile.new(@test_buckets, travis_yml_file, &block)
      end

      private

        def parse_profile_results(profile_results)

          #Input: Walnuts
          #        9.96 seconds average (69.69 seconds / 7 examples) ./spec/features/walnut_spec.rb:3
          #Output: ["9.96", "spec/features/walnut_spec.rb"]
          extracted_info = profile_results.scan(EXTRACT_DURATION_AND_FILE_PATH).uniq { |spec_file| spec_file.last }
          
          tests = extracted_info.map do |capture_groups|
            test_duration = capture_groups.first.strip.to_f
            test_file_path = capture_groups.last
            
            SpecFile.new(test_file_path, test_duration)
          end

          tests.sort_by(&:test_duration).reverse
        end

        def smallest_bucket
          @test_buckets.min_by(&:total_duration)
        end

        def distribute_tests
          @spec_files.each { |test| smallest_bucket.add_to_list(test) }
        end

    end

    class TravisFile
      include BuildMatrixParser

      def initialize(test_buckets, travis_yml_file, &block)
        rewrite_content(test_buckets, travis_yml_file)
        block.call(travis_yml_file) if block
      end

      private

        def rewrite_content(test_buckets, content)
          content['env']['matrix'] ||= [] # initialize env if not already set

          env_matrix = BuildMatrixParser.parse_env_matrix(content)

          if env_matrix.length > test_buckets.length
            env_matrix = env_matrix.slice(0, test_buckets.length)
          elsif env_matrix.length < test_buckets.length
            (test_buckets.length - env_matrix.length).times {env_matrix.push({ })}
          end

          env_matrix.each do |var_hash|
            test_bucket = test_buckets.shift

            spec_file_list = test_bucket.spec_files.map(&:file_path).join(' ')
            var_hash['TEST_SUITE'] = "#{spec_file_list}"
          end

          content['env']['matrix'] = BuildMatrixParser.format_matrix(env_matrix)
        end

    end
  
end
