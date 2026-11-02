///|
let usage : String =
  #|MoonGraft — reviewable project-template upgrades
  #|
  #|track <template-id> <revision> <rendered-template-dir> <new-baseline.json>
  #|plan <baseline.json> <project-dir> <new-revision> <new-template-dir> <new-plan.json>
  #|review <plan.json>
  #|report-json <plan.json>
  #|preview-json <resolved-plan.json>
  #|gate <resolved-plan.json> <max-removed> <max-binary-changes> <max-net-growth-bytes>
  #|review-template <plan.json> <new-review.json>
  #|apply-review <plan.json> <review.json> <new-plan.json>
  #|show <plan.json> <conflict-path>
  #|resolve <plan.json> <conflict-path> <keep-local|take-template|delete> <new-plan.json>
  #|replace <plan.json> <conflict-path> <replacement-file> <new-plan.json>
  #|export <resolved-plan.json> <project-dir> <new-bundle-dir>
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
    e => {
      @stdio.stderr.write("MoonGraft: " + e.to_string() + "\n")
      raise e
    }
  }
}
