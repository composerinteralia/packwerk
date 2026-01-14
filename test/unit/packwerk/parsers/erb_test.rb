# typed: true
# frozen_string_literal: true

require "test_helper"

module Packwerk
  module Parsers
    class ErbTest < Minitest::Test
      include TypedMock

      test "#call returns node with valid file" do
        node = File.open(fixture_path("valid.erb"), "r") do |fixture|
          Erb.new.call(io: fixture)
        end

        assert_kind_of(::AST::Node, node)
      end

      test "#call returns node with valid javascript file" do
        node = File.open(fixture_path("javascript_valid.erb"), "r") do |fixture|
          Erb.new.call(io: fixture)
        end

        assert_kind_of(NilClass, node)
      end

      test "#call writes parse error to stdout" do
        error_message = "stub error"
        err = Parser::SyntaxError.new(stub(message: error_message))
        
        # Create a mock Herb result that raises an error
        mock_result = stub(success?: true, value: stub)
        ::Herb.stubs(:parse).returns(mock_result)
        
        # Stub the visitor to raise the error
        visitor_stub = stub
        visitor_stub.stubs(:visit).raises(err)
        Erb::ErbCodeVisitor.stubs(:new).returns(visitor_stub)

        parser = Erb.new
        file_path = fixture_path("invalid.erb")

        exc = assert_raises(Parsers::ParseError) do
          File.open(file_path, "r") do |fixture|
            parser.call(io: fixture, file_path: file_path)
          end
        end

        assert_equal("Syntax error: stub error", exc.result.message)
        assert_equal(file_path, exc.result.file)
      end

      test "#call writes encoding error to stdout" do
        error_message = "stub error"
        err = EncodingError.new(error_message)
        
        # Create a mock Herb result that raises an error
        mock_result = stub(success?: true, value: stub)
        ::Herb.stubs(:parse).returns(mock_result)
        
        # Stub the visitor to raise the error
        visitor_stub = stub
        visitor_stub.stubs(:visit).raises(err)
        Erb::ErbCodeVisitor.stubs(:new).returns(visitor_stub)

        parser = Erb.new
        file_path = fixture_path("invalid.erb")

        exc = assert_raises(Parsers::ParseError) do
          File.open(file_path, "r") do |fixture|
            parser.call(io: fixture, file_path: file_path)
          end
        end

        assert_equal("stub error", exc.result.message)
        assert_equal(file_path.to_s, exc.result.file)
      end

      private

      def fixture_path(name)
        ROOT.join("test/fixtures/formats/erb", name).to_s
      end
    end
  end
end
