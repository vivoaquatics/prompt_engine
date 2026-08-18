module PromptEngine
  module ApplicationHelper
    BASE_PAGE_TITLE = "PromptEngine Admin".freeze

    # The admin stylesheets, in cascade order (foundation first, overrides last).
    #
    # These are linked individually rather than chained through CSS `@import`
    # in application.css. Propshaft does not bundle stylesheets, so an @import
    # chain forces the browser to download application.css, parse it, and only
    # then discover and serially fetch each imported file -- a waterfall that
    # produces a flash of unstyled content. Separate <link> tags download in
    # parallel and all block the first paint, so the page renders fully styled.
    STYLESHEETS = %w[
      foundation
      layout
      sidebar
      buttons
      forms
      tables
      cards
      dashboard
      prompts
      versions
      notifications
      loading
      comparison
      evaluations
      utilities
      overrides
      dark_mode
      components/_test_runs
    ].map { |name| "prompt_engine/#{name}" }.freeze

    # Emits a <link> tag per admin stylesheet, in cascade order.
    def prompt_engine_stylesheet_tags(**options)
      stylesheet_link_tag(*STYLESHEETS, **options)
    end

    # Builds the document <title>, prefixing it with the current prompt's name
    # (or an explicit content_for(:page_title)) when one is available, e.g.
    # "Blu Resolve | PromptEngine Admin".
    def admin_page_title
      prefix = content_for(:page_title).presence || @prompt&.name.presence
      [ prefix, BASE_PAGE_TITLE ].compact.join(" | ")
    end
  end
end
