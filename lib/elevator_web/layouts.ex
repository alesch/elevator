defmodule ElevatorWeb.Layouts do
  use ElevatorWeb, :html

  embed_templates "layouts/*"

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
end
