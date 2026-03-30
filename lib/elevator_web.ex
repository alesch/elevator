defmodule ElevatorWeb do
  @moduledoc """
  The industrial backbone of the Web interface.
  Centralizes functional components, layout helpers, and verified routes.
  """
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  defmacro __using__(which) when is_atom(which) do
    case which do
      :router ->
        quote do
          use Phoenix.Router, otp_app: :elevator
          import Plug.Conn
          import Phoenix.Controller
          import Phoenix.LiveView.Router
        end

      :html ->
        quote do
          use Phoenix.Component

          # Modern Phoenix 1.7+ verified mapping
          use Phoenix.VerifiedRoutes,
            endpoint: ElevatorWeb.Endpoint,
            router: ElevatorWeb.Router,
            statics: ElevatorWeb.static_paths()

          # Controller-level helpers for layouts
          import Phoenix.Controller,
            only: [
              get_csrf_token: 0,
              get_flash: 1,
              get_flash: 2,
              view_module: 1,
              view_template: 1
            ]

          import Phoenix.HTML
          import Phoenix.HTML.Form
        end

      :live_view ->
        quote do
          use Phoenix.LiveView,
            layout: {ElevatorWeb.Layouts, :app}

          # Injected HTML helpers for the dashboard
          use Phoenix.Component
          import Phoenix.HTML
          import Phoenix.HTML.Form

          use Phoenix.VerifiedRoutes,
            endpoint: ElevatorWeb.Endpoint,
            router: ElevatorWeb.Router,
            statics: ElevatorWeb.static_paths()
        end

      :live_component ->
        quote do
          use Phoenix.LiveComponent
          use Phoenix.Component
          import Phoenix.HTML
          import Phoenix.HTML.Form

          use Phoenix.VerifiedRoutes,
            endpoint: ElevatorWeb.Endpoint,
            router: ElevatorWeb.Router,
            statics: ElevatorWeb.static_paths()
        end
    end
  end
end
