defmodule ElevatorWeb.TestController do
  use Phoenix.Controller, formats: [:json]

  def reset(conn, _params) do
    Elevator.Controller.reset()
    send_resp(conn, 200, "ok")
  end
end
