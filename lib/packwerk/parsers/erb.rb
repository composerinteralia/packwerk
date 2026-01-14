# typed: strict
# frozen_string_literal: true

require "ast/node"
require "herb"

module Packwerk
  module Parsers
    class Erb
      extend T::Sig

      include ParserInterface

      sig { params(ruby_parser: Ruby).void }
      def initialize(ruby_parser: Ruby.new)
        @ruby_parser = ruby_parser
      end

      sig { override.params(io: T.any(IO, StringIO), file_path: String).returns(T.untyped) }
      def call(io:, file_path: "<unknown>")
        source = io.read
        parse_source(source, file_path: file_path)
      end

      sig { params(source: String, file_path: String).returns(T.nilable(AST::Node)) }
      def parse_source(source, file_path:)
        to_ruby_ast(source, file_path)
      rescue EncodingError => e
        result = ParseResult.new(file: file_path, message: e.message)
        raise Parsers::ParseError, result
      rescue Parser::SyntaxError => e
        result = ParseResult.new(file: file_path, message: "Syntax error: #{e}")
        raise Parsers::ParseError, result
      rescue StandardError => e
        result = ParseResult.new(file: file_path, message: "Parse error: #{e.message}")
        raise Parsers::ParseError, result
      end

      private

      sig do
        params(
          source: String,
          file_path: String
        ).returns(T.nilable(::AST::Node))
      end
      def to_ruby_ast(source, file_path)
        # Parse the ERB template and extract Ruby code segments
        result = ::Herb.parse(source)
        
        # Herb returns a result object - check if parsing was successful
        unless result.success?
          return nil
        end
        
        document = result.value
        
        # Extract Ruby code from the document
        visitor = ErbCodeVisitor.new
        visitor.visit(document)
        code_pieces = visitor.code_segments

        # Note that we're not using the source location (line/column) at the moment, but if we did
        # care about that, we'd need to tweak this to insert empty lines and spaces so that things
        # line up with the ERB file
        @ruby_parser.call(
          io: StringIO.new(code_pieces.join("\n")),
          file_path: file_path,
        )
      end

      # Visitor to extract Ruby code from Herb AST
      class ErbCodeVisitor < ::Herb::Visitor
        extend T::Sig

        sig { returns(T::Array[String]) }
        attr_reader :code_segments

        sig { void }
        def initialize
          @code_segments = T.let([], T::Array[String])
          super()
        end

        # Visit ERB output nodes (<%=)
        sig { params(node: T.untyped).void }
        def visit_erb_output_node(node)
          extract_code(node)
          super
        end

        # Visit ERB content nodes (<%)
        sig { params(node: T.untyped).void }
        def visit_erb_content_node(node)
          extract_code(node)
          super
        end

        private

        sig { params(node: T.untyped).void }
        def extract_code(node)
          # Skip ERB comments (<%#)
          return if comment?(node)
          # Skip escaped ERB (<%%
          return if escape?(node)

          # Extract the Ruby code from the node
          code = node.content.value
          @code_segments << code if code && !code.strip.empty?
        end

        sig { params(node: T.untyped).returns(T::Boolean) }
        def comment?(node)
          node.tag_opening.value == "<%#"
        end

        sig { params(node: T.untyped).returns(T::Boolean) }
        def escape?(node)
          node.tag_opening.value == "<%%"
        end
      end
    end
  end
end
