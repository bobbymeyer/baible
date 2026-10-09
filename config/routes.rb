Rails.application.routes.draw do
  # Signing in (Authentication); there is no sign-up page (README "Setup").
  resource :session
  resources :passwords, param: :token

  # Where ComfyUI and the language model are (SiteSetting), with a check.
  resource :settings, only: %i[show update]

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
  # subject made of it; editing it; and the notes on it.
  resources :entries, only: %i[show edit update destroy] do
    scope module: :entries do
      resources :notes, only: %i[create destroy]
    end
  end

  # A subject's studio (show), its own layer (edit), its variants, and the
  # batches that make candidates for it; the panel is the batches alone, for
  # the frame that reloads as files land.
  resources :subjects, only: %i[show edit update destroy] do
    scope module: :subjects do
      resources :variants, only: %i[create update destroy]
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

  root "projects#index"
end
