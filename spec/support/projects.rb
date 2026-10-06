# frozen_string_literal: true

# A project to work in: the starter kinds from config/comfy.yml, and
# subjects in them.
module ProjectHelpers
  def make_project(name = "The Drowned Coast", **attrs)
    Project.create!(name: name, **attrs).tap(&:add_starter_kinds!)
  end

  def make_subject(project, kind_name, name, **attrs)
    project.subjects.create!(kind: project.kinds.find_by!(name: kind_name), name: name, **attrs)
  end

  # Submit a batch, have ComfyUI finish everything, and collect it.
  def finish(batch, comfy)
    BatchJob.new.perform(batch.reload, client: comfy)
    comfy.finish!(*comfy.submitted.each_index.map { |i| "prompt-#{i + 1}" })
    BatchJob.new.perform(batch.reload, client: comfy)
    batch.reload
  end
end

RSpec.configure { |config| config.include ProjectHelpers }
