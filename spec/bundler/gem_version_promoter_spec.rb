# frozen_string_literal: true

RSpec.describe Bundler::GemVersionPromoter do
  let(:gvp) { described_class.new }

  # Rightmost (highest array index) in result is most preferred.
  # Leftmost (lowest array index) in result is least preferred.
  # `build_candidates` has all versions of gem in index.
  # `build_spec` is the version currently in the .lock file.
  #
  # In default (not strict) mode, all versions in the index will
  # be returned, allowing Bundler the best chance to resolve all
  # dependencies, but sometimes resulting in upgrades that some
  # would not consider conservative.

  describe "#sort_versions" do
    def build_candidates(versions)
      versions.map do |v|
        Bundler::Resolver::Candidate.new(v)
      end
    end

    def build_package(name, version, unlock)
      Bundler::Resolver::Package.new(name, [], locked_specs: Bundler::SpecSet.new(build_spec(name, version)), unlock: unlock)
    end

    def sorted_versions(candidates:, current:, unlock: true)
      gvp.sort_versions(
        build_package("foo", current, unlock),
        build_candidates(candidates)
      ).flatten.map(&:version).map(&:to_s)
    end

    it "numerically sorts versions" do
      versions = sorted_versions(candidates: %w[1.7.7 1.7.8 1.7.9 1.7.15 1.8.0], current: "1.7.8")
      expect(versions).to eq %w[1.8.0 1.7.15 1.7.9 1.7.8 1.7.7]
    end

    context "with no options" do
      it "defaults to level=:major, strict=false, pre=false" do
        versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
        expect(versions).to eq %w[2.1.0 2.0.1 1.0.0 0.9.0 0.3.1 0.3.0 0.2.0]
      end
    end

    context "when strict" do
      before { gvp.strict = true }

      context "when level is major" do
        before { gvp.level = :major }

        it "keeps downgrades" do
          versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
          expect(versions).to eq %w[2.1.0 2.0.1 1.0.0 0.9.0 0.3.1 0.3.0 0.2.0]
        end
      end

      context "when level is minor" do
        before { gvp.level = :minor }

        it "sorts highest minor within same major in first position" do
          versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
          expect(versions).to eq %w[0.9.0 0.3.1 0.3.0 1.0.0 2.1.0 2.0.1 0.2.0]
        end
      end

      context "when level is patch" do
        before { gvp.level = :patch }

        it "sorts highest patch within same minor in first position" do
          versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
          expect(versions).to eq %w[0.3.1 0.3.0 0.9.0 1.0.0 2.0.1 2.1.0 0.2.0]
        end
      end
    end

    context "when not strict" do
      before { gvp.strict = false }

      context "when level is major" do
        before { gvp.level = :major }

        it "orders by version" do
          versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
          expect(versions).to eq %w[2.1.0 2.0.1 1.0.0 0.9.0 0.3.1 0.3.0 0.2.0]
        end
      end

      context "when level is minor" do
        before { gvp.level = :minor }

        it "favors minor upgrades, then patch upgrades, then major upgrades, then downgrades" do
          versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
          expect(versions).to eq %w[0.9.0 0.3.1 0.3.0 1.0.0 2.1.0 2.0.1 0.2.0]
        end
      end

      context "when level is patch" do
        before { gvp.level = :patch }

        it "favors patch upgrades, then minor upgrades, then major upgrades, then downgrades" do
          versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.1 2.1.0], current: "0.3.0")
          expect(versions).to eq %w[0.3.1 0.3.0 0.9.0 1.0.0 2.0.1 2.1.0 0.2.0]
        end
      end
    end

    context "when pre" do
      before { gvp.pre = true }

      it "sorts regardless of prerelease status" do
        versions = sorted_versions(candidates: %w[1.7.7.pre 1.8.0 1.8.1.pre 1.8.1 2.0.0.pre 2.0.0], current: "1.8.0")
        expect(versions).to eq %w[2.0.0 2.0.0.pre 1.8.1 1.8.1.pre 1.8.0 1.7.7.pre]
      end
    end

    context "when not pre" do
      before { gvp.pre = false }

      it "deprioritizes prerelease gems" do
        versions = sorted_versions(candidates: %w[1.7.7.pre 1.8.0 1.8.1.pre 1.8.1 2.0.0.pre 2.0.0], current: "1.8.0")
        expect(versions).to eq %w[2.0.0 1.8.1 1.8.0 2.0.0.pre 1.8.1.pre 1.7.7.pre]
      end
    end

    context "when locking and not major" do
      before { gvp.level = :minor }

      it "keeps the current version first" do
        versions = sorted_versions(candidates: %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.1.0 2.0.1], current: "0.3.0", unlock: [])
        expect(versions.first).to eq("0.3.0")
      end
    end
  end

  describe "#filter_versions" do
    def build_candidates(versions)
      versions.map do |v|
        Bundler::Resolver::Candidate.new(v)
      end
    end

    def build_package(name, version)
      Bundler::Resolver::Package.new(name, [], locked_specs: Bundler::SpecSet.new(build_spec(name, version)), unlock: [])
    end

    def filtered_versions(candidates:, current:)
      gvp.filter_versions(
        build_package("foo", current),
        build_candidates(candidates)
      ).map {|candidate| candidate.version.to_s }
    end

    let(:candidates) { %w[0.9.0 1.0.0 1.2.0 1.3.1 2.0.0 2.5.1 3.0.0 4.1.0] }

    context "when not strict" do
      it "returns every candidate, whatever the level" do
        gvp.level = :major

        expect(filtered_versions(candidates: candidates, current: "1.2.0")).to eq candidates
      end
    end

    context "when strict" do
      before { gvp.strict = true }

      context "when level is major" do
        before { gvp.level = :major }

        it "allows the next major but not the majors beyond it" do
          expect(filtered_versions(candidates: candidates, current: "1.2.0")).to eq %w[1.2.0 1.3.1 2.0.0 2.5.1]
        end

        it "excludes downgrades" do
          expect(filtered_versions(candidates: candidates, current: "1.2.0")).not_to include("0.9.0", "1.0.0")
        end

        it "allows every remaining version when already on the highest major" do
          expect(filtered_versions(candidates: %w[4.1.0 4.2.0 5.0.0], current: "4.1.0")).to eq %w[4.1.0 4.2.0 5.0.0]
        end

        it "returns nothing when only later majors are available" do
          expect(filtered_versions(candidates: %w[3.0.0 4.1.0], current: "1.2.0")).to eq []
        end
      end

      context "when level is minor" do
        before { gvp.level = :minor }

        it "stays within the locked major" do
          expect(filtered_versions(candidates: candidates, current: "1.2.0")).to eq %w[1.2.0 1.3.1]
        end
      end

      context "when level is patch" do
        before { gvp.level = :patch }

        it "stays within the locked minor" do
          expect(filtered_versions(candidates: candidates, current: "1.2.0")).to eq %w[1.2.0]
        end
      end
    end
  end

  describe "#level=" do
    subject { described_class.new }

    it "should raise if not major, minor or patch is passed" do
      expect { subject.level = :minjor }.to raise_error ArgumentError
    end

    it "should raise if invalid classes passed" do
      [123, nil].each do |value|
        expect { subject.level = value }.to raise_error ArgumentError
      end
    end

    it "should accept major, minor patch symbols" do
      [:major, :minor, :patch].each do |value|
        subject.level = value
        expect(subject.level).to eq value
      end
    end

    it "should accept major, minor patch strings" do
      %w[major minor patch].each do |value|
        subject.level = value
        expect(subject.level).to eq value.to_sym
      end
    end
  end
end
