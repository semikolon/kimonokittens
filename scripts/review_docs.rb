#!/usr/bin/env ruby

require 'colorize'
require 'yaml'
require 'json'

puts "=================================================".blue
puts " Documentation Review".blue
puts "=================================================\n".blue

puts "This script provides a structured overview of project documentation to facilitate a 'Total Recap' or review.".yellow
puts "Review the 'Must Review' documents to grasp the project's goals.".yellow
puts "To understand the current implementation, focus on the 'Key Code Implementation' section and recent git history.\n".yellow

# --- 1. Core Strategy & Blueprints (Must Review) ---
puts "--- 1. Core Strategy & Blueprints (Must Review) ---\n".green

core_strategy_docs = [
  "README.md",
  "VISION.md", 
  "DEVELOPMENT.md"
].select { |f| File.exist?(f) }

core_strategy_docs.each { |doc| puts "- #{doc}" }
puts "\n"

# --- 2. Active Project Plans (Must Review) ---
puts "--- 2. Active Project Plans (Must Review) ---\n".green

active_plans = [
  "TODO.md",
  "DONE.md",
  "STRATEGY_2025.md"
].select { |f| File.exist?(f) }

active_plans.each { |doc| puts "- #{doc}" }
puts "\n"

# --- 3. Key Code Implementation (Review for Recent Changes) ---
puts "--- 3. Key Code Implementation (Review for Recent Changes) ---\n".green

key_code_files = [
  "rent.rb"
].select { |f| File.exist?(f) }

# # Add any other Python files in loom/ directory
# loom_files = Dir.glob("loom/*.py").reject { |f| key_code_files.include?(f) }
# key_code_files.concat(loom_files)

# Add integration specs
integration_specs = Dir.glob("spec/integration/*.rb")
key_code_files.concat(integration_specs.reject { |f| key_code_files.include?(f) })

key_code_files.each { |file| puts "- #{file}" }
puts "\n"

# --- 4. Core Principles & Rules (Review if Unfamiliar) ---
puts "--- 4. Core Principles & Rules (Review if Unfamiliar) ---\n".green

rule_files = Dir.glob(".cursor/rules/*.mdc")
if rule_files.any?
  rule_files.each do |rule_file|
    begin
      content = File.read(rule_file)
      summary = ""
      # Check for YAML front-matter
      if content =~ /\A---\s*\n(.*?\n)---\s*\n/m
        front_matter = YAML.safe_load($1) || {}

        if front_matter['alwaysApply'] == true
          summary = "(always applied)".cyan
        else
          globs = front_matter['globs']
          if globs && !globs.empty?
            summary = "(globs: #{globs.join(', ')})".cyan
          else
            desc = front_matter['description']
            if desc && !desc.strip.empty?
              # Truncate for display
              truncated_desc = desc.strip.gsub(/\s+/, ' ')[0..70]
              truncated_desc += "..." if desc.length > 70
              summary = "(requestable: #{truncated_desc})".cyan
            end
          end
        end
      end
      puts "- #{rule_file} #{summary}"
    rescue => e
      puts "- #{rule_file} ".red + "(Error processing: #{e.message})".red
    end
  end
else
  puts "No rule files found.".red
end
puts "\n"

# --- 5. Supporting Technical Docs (Consult as Needed) ---
puts "--- 5. Supporting Technical Docs (Consult as Needed) ---\n".green

supporting_docs = [
].select { |f| File.exist?(f) }

# Add any other markdown files not already categorized
other_docs = Dir.glob("*.md").reject do |f|
  core_strategy_docs.include?(f) || 
  active_plans.include?(f) || 
  supporting_docs.include?(f) ||
  f.start_with?("ai_development_o3")
end

# Ignore patterns for workspace hygiene
ignore_patterns = [".venv/", "venv", "ticktick_env", "transcripts/", ".worktrees/"]
other_docs = other_docs.reject do |f|
  ignore_patterns.any? { |pattern| f.include?(pattern) }
end

supporting_docs.concat(other_docs)
supporting_docs.each { |doc| puts "- #{doc}" }
puts "\n"

# --- 6. Historical Milestones (Consult as Needed) ---
puts "--- 6. Historical Milestones (Consult as Needed) ---\n".green

milestone_docs = Dir.glob("docs/milestones/*.md")
if milestone_docs.any?
  milestone_docs.each { |doc| puts "- #{doc}" }
else
  puts "No milestone documents found.".red
end
puts "\n"

puts "=================================================".blue
puts " End of Review List".blue
puts "=================================================".blue

# Machine-parsable output for downstream automation
puts "\n# MACHINE_PARSABLE_OUTPUT".blue
machine_output = {
  "core_strategy" => core_strategy_docs,
  "active_plans" => active_plans,
  "key_code" => key_code_files,
  "core_rules" => rule_files,
  "supporting_docs" => supporting_docs,
  "milestones" => milestone_docs
}

puts JSON.pretty_generate(machine_output) 