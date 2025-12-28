#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

def calculate_file_coverage(lines)
  return 0.0 if lines.nil? || lines.empty?

  relevant_lines = lines.reject(&:nil?)
  return 0.0 if relevant_lines.empty?

  covered = relevant_lines.count { |line| line && line > 0 }
  total = relevant_lines.count

  (covered.to_f / total * 100).round(2)
end

def extract_file_path(full_path)
  # Remove workspace root and get relative path
  workspace_root = Pathname.new(__dir__).parent.realpath
  file_path = Pathname.new(full_path)
  
  if file_path.to_s.start_with?(workspace_root.to_s)
    file_path.relative_path_from(workspace_root).to_s
  else
    # Fallback: try to extract relative path
    full_path.sub(%r{.*/(lib|app)/}, '\1/')
  end
end

def parse_coverage_data
  coverage_dir = Pathname.new(__dir__).parent.join("coverage")
  resultset_file = coverage_dir.join(".resultset.json")
  last_run_file = coverage_dir.join(".last_run.json")

  unless resultset_file.exist?
    puts "Error: Coverage resultset file not found at #{resultset_file}"
    exit 1
  end

  resultset_data = JSON.parse(File.read(resultset_file))
  last_run_data = last_run_file.exist? ? JSON.parse(File.read(last_run_file)) : {}

  # Get the first (and usually only) test suite result
  test_suite_key = resultset_data.keys.first
  coverage_data = resultset_data[test_suite_key]["coverage"] || {}

  file_coverage = {}
  total_lines = 0
  total_covered = 0

  coverage_data.each do |full_path, file_data|
    next unless file_data["lines"]

    relative_path = extract_file_path(full_path)
    # Skip files in spec, vendor, etc.
    next if relative_path.include?("/spec/") || relative_path.include?("/vendor/")

    lines = file_data["lines"]
    coverage_percentage = calculate_file_coverage(lines)
    
    # Count relevant lines (non-nil lines)
    relevant_lines = lines.reject(&:nil?)
    covered_lines = relevant_lines.count { |line| line && line > 0 }

    file_coverage[relative_path] = {
      percentage: coverage_percentage,
      total_lines: relevant_lines.count,
      covered_lines: covered_lines,
      missed_lines: relevant_lines.count - covered_lines
    }

    total_lines += relevant_lines.count
    total_covered += covered_lines
  end

  total_coverage = total_lines > 0 ? (total_covered.to_f / total_lines * 100).round(2) : 0.0

  {
    file_coverage: file_coverage.sort_by { |_k, v| -v[:percentage] },
    total_coverage: total_coverage,
    total_lines: total_lines,
    total_covered: total_covered
  }
end

def generate_markdown(coverage_info)
  markdown = "# Code Coverage Report\n\n"
  markdown += "**Total Coverage: #{coverage_info[:total_coverage]}%**\n\n"
  markdown += "Covered: #{coverage_info[:total_covered]} / #{coverage_info[:total_lines]} lines\n\n"
  markdown += "---\n\n"
  markdown += "## File Coverage\n\n"
  markdown += "| File | Coverage | Covered Lines | Missed Lines | Total Lines |\n"
  markdown += "|------|----------|---------------|--------------|-------------|\n"

  coverage_info[:file_coverage].each do |file_path, data|
    status_icon = data[:percentage] >= 90 ? "✅" : data[:percentage] >= 70 ? "⚠️" : "❌"
    markdown += "| `#{file_path}` | #{data[:percentage]}% #{status_icon} | #{data[:covered_lines]} | #{data[:missed_lines]} | #{data[:total_lines]} |\n"
  end

  markdown += "\n---\n\n"
  markdown += "*Report generated automatically from SimpleCov results*\n"
  markdown += "*To regenerate: Run `bundle exec rspec` and then `ruby scripts/generate_coverage_report.rb`*\n"

  markdown
end

# Main execution
begin
  coverage_info = parse_coverage_data
  markdown_content = generate_markdown(coverage_info)
  
  output_file = Pathname.new(__dir__).parent.join("COVERAGE.md")
  File.write(output_file, markdown_content)
  
  puts "Coverage report generated: #{output_file}"
  puts "Total Coverage: #{coverage_info[:total_coverage]}%"
rescue => e
  puts "Error generating coverage report: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

