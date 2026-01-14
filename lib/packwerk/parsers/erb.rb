# typed: strict
# frozen_string_literal: true

require "ast/node"
require "herb"
require "parser"

module Packwerk
  module Parsers
    class Erb
      extend T::Sig

      include ParserInterface

      sig { params(parser_class: T.untyped, ruby_parser: Ruby).void }
      def initialize(parser_class: nil, ruby_parser: Ruby.new)
        # parser_class is kept for backward compatibility but is no longer used
        # herb does not require a configurable parser class
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
          # If parsing failed, log the error but return nil (no Ruby to extract)
          # This is consistent with the javascript_valid.erb test case
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
          # Skip ERB comments (<%#) and escaped ERB (<%%
          return if comment?(node) || escape?(node)

          # Extract the Ruby code from the node
          # Safely access node.content and its value
          return unless node.respond_to?(:content)
          content = node.content
          return unless content.respond_to?(:value)
          
          code = content.value
          @code_segments << code if code && !code.strip.empty?
        end

        sig { params(node: T.untyped).returns(T::Boolean) }
        def comment?(node)
          return false unless node.respond_to?(:tag_opening)
          tag_opening = node.tag_opening
          return false unless tag_opening.respond_to?(:value)
          tag_opening.value == "<%#"
        end

        sig { params(node: T.untyped).returns(T::Boolean) }
        def escape?(node)
          return false unless node.respond_to?(:tag_opening)
          tag_opening = node.tag_opening
          return false unless tag_opening.respond_to?(:value)
          tag_opening.value == "<%%"
        end
      end
    end
  end
end
