# frozen_string_literal: true

require 'English'
require 'shellwords'

module Diffdash
  class GitContext
    def initialize(base_ref: nil)
      @base_ref = base_ref || detect_base_ref
    end

    def branch_name
      result = run_git('branch', '--show-current')
      branch = result.strip

      raise GitContextError, 'Could not determine branch name. Ensure you are on a branch.' if branch.empty?

      branch
    end

    def changed_files
      # Try to get files changed in this PR/branch compared to base
      files = diff_against_base

      # Fallback: if no diff found, get uncommitted changes
      files = uncommitted_changes if files.empty?

      # Fallback: staged files
      files = staged_files if files.empty?

      files.map { |f| File.expand_path(f) }
    end

    private

    def detect_base_ref
      # Common base branch names
      %w[main master develop].each do |base|
        return base if branch_exists?(base)
      end
      'HEAD~10' # Fallback to recent commits
    end

    def branch_exists?(name)
      output = run_git('rev-parse', '--verify', name, allow_failure: true)
      !output.strip.empty?
    end

    def diff_against_base
      # Special handling for GitHub Actions pull requests
      return github_pr_changed_files if github_pr_context?

      merge_base = run_git('merge-base', @base_ref, 'HEAD', allow_failure: true).strip
      return [] if merge_base.empty?

      result = run_git('diff', '--name-only', merge_base, 'HEAD', allow_failure: true)

      result.split("\n").reject(&:empty?)
    end

    def github_pr_context?
      ENV['GITHUB_ACTIONS'] == 'true' && ENV['GITHUB_EVENT_NAME'] == 'pull_request'
    end

    def github_pr_changed_files
      # In GitHub Actions PR context, compare against the base branch
      # GitHub checks out a merge commit, so we compare HEAD against origin/base
      base_ref = ENV['GITHUB_BASE_REF'] || @base_ref

      # First, ensure we have the base ref
      run_git('fetch', 'origin', base_ref, allow_failure: true)

      # Use three-dot diff to get only the commits in the PR branch
      result = run_git('diff', '--name-only', "origin/#{base_ref}...HEAD", allow_failure: true)

      result.split("\n").reject(&:empty?)
    end

    def uncommitted_changes
      result = run_git('diff', '--name-only', 'HEAD', allow_failure: true)

      result.split("\n").reject(&:empty?)
    end

    def staged_files
      result = run_git('diff', '--name-only', '--cached', allow_failure: true)

      result.split("\n").reject(&:empty?)
    end

    def run_git(*args, allow_failure: false)
      cmd = "git #{args.map { |a| Shellwords.shellescape(a) }.join(' ')} 2>/dev/null"
      output = `#{cmd}`
      raise GitContextError, "Git command failed: git #{args.join(' ')}" unless allow_failure || $CHILD_STATUS.success?

      output
    end
  end
end
