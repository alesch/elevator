defmodule ElevatorWeb.Router do
  use ElevatorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElevatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ElevatorWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
  end
end
