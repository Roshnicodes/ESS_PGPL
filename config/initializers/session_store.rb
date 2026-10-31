# Own cookie name and path, so PGPL ESS and ASA ESS never overwrite each other's login cookie on the same domain.
Rails.application.config.session_store :cookie_store, key: "_ess_pgpl_session",
  path: Rails.application.config.relative_url_root.presence || "/"
