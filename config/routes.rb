Rails.application.routes.draw do
  # Signing in (Authentication); there is no sign-up page (README "Setup").
  resource :session
  resources :passwords, param: :token

  # Where ComfyUI and the language model are (SiteSetting), with a check.
  resource :settings, only: %i[show update]

  # Models and workflows the language model learns (docs/HANDOFF.md "Unknown
  # models and new workflows"): proposed, edited, tried and accepted.
  resource :learning, only: :show
  %i[learned_families learned_workflows].each do |learned|
    resources learned, only: %i[create update destroy] do
      resource :trial, only: :create, controller: "learnables/trials"
      resource :acceptance, only: :create, controller: "learnables/acceptances"
    end
  end

  # Overnight: what's queued for tonight's window, and what last night made,
  # for review (NightShift).
  resource :night, only: :show
  # Standing orders: what the night shift plans for itself every night.
  resources :standing_orders, only: %i[create update destroy]

  # Projects, the top layer; their kinds (the middle layer, "art direction"),
  # their entries (the bible: Cid, across every kind he's made in), and making
  # subjects in them. A project's manifest lists its picks.
  resources :projects do
    scope module: :projects do
      resources :kinds, except: :show
      resources :entries, only: %i[index new create]
      resources :subjects, only: %i[new create]
      resource :manifest, only: :show
    end
  end

  # An entry's page in the bible (show): its lore, its look and every
  # subject made of it; editing it; the notes on it; and its LoRA training
  # sets (index: the runs alone, for their frame to reload).
  resources :entries, only: %i[show edit update destroy] do
    scope module: :entries do
      resources :notes, only: %i[create destroy]
      resources :trainings, only: %i[index new create]
    end
  end

  # A training run: training a kept set (run), the entry using its LoRA or
  # not (use), its set as a .tar (set), its LoRA file (lora), and deleting it.
  resources :trainings, only: :destroy do
    scope module: :trainings do
      resource :run, only: %i[create destroy]
      resource :use, only: %i[create destroy]
      resource :set, only: :show
      resource :lora, only: :show
    end
  end

  # A subject's studio (show), its own layer (edit), its variants, the
  # subjects derived from it (Cid's portrait, his design sheet), and the
  # batches that make candidates for it; the panel is the batches alone, for
  # the frame that reloads as files land.
  resources :subjects, only: %i[show edit update destroy] do
    scope module: :subjects do
      resources :variants, only: %i[create update destroy]
      resources :derivations, only: :create
      resources :batches, only: %i[create destroy]
      resource :panel, only: :show
    end
  end

  # Picking a candidate, or making a draft properly.
  resources :candidates, only: [] do
    scope module: :candidates do
      resource :pick, only: :create
      resource :refinement, only: :create
    end
  end

  # What leaves baible: a pick's file and its sidecar (docs/HANDOFF.md "Export").
  # A pick from the history used again (current), or approved as its
  # target's canon; letting one go (destroy).
  resources :picks, only: :destroy do
    scope module: :picks do
      resource :current, only: :create
      resource :canon, only: %i[create destroy]
      resource :download, only: :show
      resource :sidecar, only: :show
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
  # The health a deploy gate can trust: 200 only once the database answered
  # (HealthController). /up and the signed-out redirect never touch it.
  resource :health, only: :show, controller: "health"

  root "projects#index"
end
