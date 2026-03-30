defmodule ElevatorWeb.ErrorHTML do
  use ElevatorWeb, :html

  # If you want to customize your error pages, you can
  # expose a template per status code here.
  # def render("404.html", _assigns), do: "Page not found"
  # def render("500.html", _assigns), do: "Internal server error"

  # For simple cases, we can just use the status message
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
