///|
let usage : String =
  #|MoonGraft — reviewable project-template upgrades
  #|
  #|capture-git <local-repo> <commit-sha> <subdir-or-dot> <new-source.json>
  #|create-git <source.json> <new-bundle-dir>
  #|check-git <source.json> <target-commit-sha>
  #|track <template-id> <revision> <rendered-template-dir> <new-baseline.json>
  #|plan <baseline.json> <project-dir> <new-revision> <new-template-dir> <new-plan.json>
  #|review <plan.json>
  #|report-json <plan.json>
  #|preview-json <resolved-plan.json>
  #|drift-json <plan.json> <project-dir>
  #|refresh <plan.json> <project-dir> <new-plan.json>
  #|protect <resolved-plan.json> <protected-paths.json>
  #|gate <resolved-plan.json> <max-removed> <max-binary-changes> <max-net-growth-bytes>
  #|review-template <plan.json> <new-review.json>
  #|apply-review <plan.json> <review.json> <new-plan.json>
  #|show <plan.json> <conflict-path>
  #|resolve <plan.json> <conflict-path> <keep-local|take-template|delete> <new-plan.json>
  #|replace <plan.json> <conflict-path> <replacement-file> <new-plan.json>
  #|export <resolved-plan.json> <project-dir> <new-bundle-dir>
  #|export-checked <resolved-plan.json> <project-dir> <policy.json> <new-bundle-dir>
  #|resume <bundle-dir>
  #|verify-export <bundle-dir>
  #|rollback-export <resolved-plan.json> <candidate-project-dir> <new-bundle-dir>
  #|
  #|Archives are created exclusively. Root .git metadata is explicitly excluded.
  #|Source project files are never overwritten. See README.md for supported inputs.

///|
fn show_file(label : String, file : @graft.File?) -> Unit {
  println("--- " + label + " ---")
  match file {
    None => println("(absent)")
    Some(file) => {
      println(
        "Bytes: " +
        file.content.length().to_string() +
        "; executable: " +
        file.executable.to_string(),
      )
      let text = @utf8.decode(file.content, ignore_bom=false) catch {
        _ => {
          println("(binary; original bytes remain in the plan archive)")
          return
        }
      }
      println(text)
    }
  }
}

///|
async fn run(args : Array[String]) -> Unit {
  match args {
    [] | ["--help"] | ["-h"] => println(usage)
    ["capture-git", repository, revision, subdir, output] => {
      let source = @workspace.capture_git_source(
        repository,
        revision,
        if subdir == "." {
          ""
        } else {
          subdir
        },
      )
      @workspace.require_outside(output, source.repository)
      @workspace.write_new(output, source.encode())
      println("Recorded Git template source: " + output)
    }
    ["create-git", input, output] => {
      let source = @workspace.GitSource::decode(@workspace.read_text(input))
      source.create_project(output)
      println("Verified generated project: " + output + "/project")
    }
    ["check-git", input, revision] => {
      let source = @workspace.GitSource::decode(@workspace.read_text(input))
      let target = source.at(revision)
      if source.baseline.revision == target.baseline.revision {
        println("Already recorded: " + revision)
      } else if source.baseline.tree == target.baseline.tree {
        println("New commit with identical template files: " + revision)
      } else {
        println("New commit with template changes: " + revision)
      }
    }
    ["track", id, revision, root, output] => {
      let baseline = @graft.track(id, revision, @workspace.scan(root))
      @workspace.write_new(output, baseline.encode())
      println("Recorded template baseline: " + output)
    }
    ["plan", input, project, revision, template, output] => {
      let baseline = @graft.Baseline::decode(@workspace.read_text(input))
      let next = @graft.track(
        baseline.template_id,
        revision,
        @workspace.scan(template),
      )
      let plan = @graft.plan_update(baseline, @workspace.scan(project), next)
      @workspace.write_new(output, plan.encode())
      println(plan.report())
    }
    ["review", input] =>
      println(@graft.Plan::decode(@workspace.read_text(input)).report())
    ["report-json", input] =>
      println(@graft.Plan::decode(@workspace.read_text(input)).report_json())
    ["preview-json", input] =>
      println(@graft.Plan::decode(@workspace.read_text(input)).output_json())
    ["drift-json", input, project] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      println(plan.drift_json(@workspace.scan(project)))
    }
    ["refresh", input, project, output] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      let refreshed = plan.refresh(@workspace.scan(project))
      @workspace.write_new(output, refreshed.plan.encode())
      println("Retained decisions: " + refreshed.retained.join(", "))
      println("Dropped decisions: " + refreshed.dropped.join(", "))
      println(refreshed.plan.report())
    }
    ["protect", input, rules] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      plan.check_protected_json(@workspace.read_text(rules))
      println("Protected path policy passed")
    }
    ["gate", input, removed, binary, growth] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      plan.check_policy(
        max_removed=@string.parse_int(removed),
        max_binary_changes=@string.parse_int(binary),
        max_growth_bytes=@string.parse_int(growth),
      )
      println("Upgrade policy passed")
    }
    ["review-template", input, output] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      @workspace.write_new(output, plan.review_template())
    }
    ["apply-review", input, review, output] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      let resolved = plan.resolve_review(@workspace.read_text(review))
      @workspace.write_new(output, resolved.encode())
      println(resolved.report())
    }
    ["show", input, path] => {
      let detail = @graft.Plan::decode(@workspace.read_text(input)).conflict_detail(
        path,
      )
      show_file("base", detail.base)
      show_file("project", detail.project)
      show_file("template", detail.template)
    }
    ["resolve", input, path, action, output] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      let resolution = match action {
        "keep-local" => @graft.KeepLocal
        "take-template" => @graft.TakeTemplate
        "delete" => @graft.Delete
        _ =>
          raise @workspace.WorkspaceError(
            "Unknown decision: " + action + "\n" + usage,
          )
      }
      let resolved = plan.resolve([@graft.Decision::new(path, resolution)])
      @workspace.write_new(output, resolved.encode())
      println(resolved.report())
    }
    ["replace", input, path, replacement, output] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      let file = @workspace.read_file(replacement, path)
      let resolved = plan.resolve([
        @graft.Decision::new(path, @graft.Replace(file)),
      ])
      @workspace.write_new(output, resolved.encode())
      println(resolved.report())
    }
    ["export", input, project, destination] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      @workspace.require_outside(destination, project)
      let applied = plan.apply(@workspace.scan(project))
      @workspace.export_result(applied, destination)
      println("Verified candidate: " + destination + "/project")
      println("Next template baseline: " + destination + "/baseline.json")
    }
    ["export-checked", input, project, policy, destination] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      @workspace.require_outside(destination, project)
      let applied = plan.prepare(
        @workspace.scan(project),
        @workspace.read_text(policy),
      )
      @workspace.export_result(applied, destination)
      println("Policy-checked candidate: " + destination + "/project")
    }
    ["resume", destination] => {
      @workspace.resume_export(destination)
      println("Verified candidate: " + destination + "/project")
    }
    ["verify-export", destination] => {
      @workspace.verify_export(destination)
      println("Candidate verified without writing: " + destination)
    }
    ["rollback-export", input, candidate, destination] => {
      let plan = @graft.Plan::decode(@workspace.read_text(input))
      @workspace.require_outside(destination, candidate)
      let restored = plan.rollback(@workspace.scan(candidate))
      @workspace.export_result(restored, destination)
      println("Verified rollback candidate: " + destination + "/project")
    }
    _ => raise @workspace.WorkspaceError("Invalid arguments.\n" + usage)
  }
}

///|
async fn main {
  run(@env.args()[1:].to_owned()) catch {
    @graft.GraftError::_ as e => {
      @stdio.stderr.write("MoonGraft: " + e.message() + "\n")
      raise e
    }
    @workspace.WorkspaceError(message) as e => {
      @stdio.stderr.write("MoonGraft: " + message + "\n")
      raise e
    }
    e => {
      @stdio.stderr.write("MoonGraft: " + e.to_string() + "\n")
      raise e
    }
  }
}
