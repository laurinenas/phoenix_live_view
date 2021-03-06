defmodule Phoenix.LiveView.LiveViewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias Phoenix.LiveViewTest.{Endpoint, ThermostatView, ClockView, ClockControlsView}

  def session(view) do
    {:ok, session} = Phoenix.LiveView.View.verify_session(view.endpoint, view.token)
    session
  end

  describe "mounting" do
    test "mount with disconnected module" do
      {:ok, _view, html} = mount(Endpoint, ThermostatView)
      assert html =~ "The temp is: 1"
    end
  end

  describe "rendering" do
    setup do
      {:ok, view, html} = mount_disconnected(Endpoint, ThermostatView, session: %{})
      {:ok, view: view, html: html}
    end

    test "live render with valid session", %{view: view, html: html} do
      assert html =~ """
             The temp is: 0
             <button phx-click="dec">-</button>
             <button phx-click="inc">+</button>
             """

      {:ok, view, html} = mount(view)
      assert is_pid(view.pid)

      assert html =~ """
             The temp is: 1
             <button phx-click="dec">-</button>
             <button phx-click="inc">+</button>
             """
    end

    test "live render with bad session", %{view: view} do
      assert {:error, %{reason: "badsession"}} =
               mount(%Phoenix.LiveViewTest.View{view | token: "bad"})
    end

    test "render_submit", %{view: view} do
      {:ok, view, _} = mount(view)
      assert render_submit(view, :save, %{temp: 20}) =~ "The temp is: 20"
    end

    test "render_change", %{view: view} do
      {:ok, view, _} = mount(view)
      assert render_change(view, :save, %{temp: 21}) =~ "The temp is: 21"
    end

    @key_i 73
    @key_d 68
    test "render_key|up|down", %{view: view} do
      {:ok, view, _} = mount(view)
      assert render(view) =~ "The temp is: 1"
      assert render_keyup(view, :key, @key_i) =~ "The temp is: 2"
      assert render_keydown(view, :key, @key_d) =~ "The temp is: 1"
      assert render_keyup(view, :key, @key_d) =~ "The temp is: 0"
      assert render(view) =~ "The temp is: 0"
    end

    test "render_blur and render_focus", %{view: view} do
      {:ok, view, _} = mount(view)
      assert render(view) =~ "The temp is: 1"
      assert render_blur(view, :inactive, "Zzz") =~ "Tap to wake – Zzz"
      assert render_focus(view, :active, "Hello!") =~ "Waking up – Hello!"
    end

    test "custom DOM container attributes" do
      {:ok, view, static_html} =
        mount_disconnected(Endpoint, ThermostatView,
          session: %{nest: [attrs: [style: "clock-flex"]]},
          attrs: [style: "thermo-flex<script>"]
        )

      {:ok, view, mount_html} = mount(view)

      assert static_html =~ ~r/style=\"thermo-flex&lt;script&gt;\"[^>]* data-phx-view=\"Phoenix.LiveViewTest.ThermostatView/
      assert static_html =~ ~r/style=\"clock-flex\"[^>]* data-phx-view=\"Phoenix.LiveViewTest.ClockView/

      assert mount_html =~ ~r/style=\"clock-flex\"[^>]* data-phx-view=\"Phoenix.LiveViewTest.ClockView/
      assert render(view) =~ ~r/style=\"clock-flex\"[^>]* data-phx-view=\"Phoenix.LiveViewTest.ClockView/
    end
  end

  describe "messaging callbacks" do
    test "handle_event with no change in socket" do
      {:ok, view, html} = mount(Endpoint, ThermostatView)
      assert html =~ "The temp is: 1"
      assert render_click(view, :noop) == html
    end

    test "handle_info with change" do
      {:ok, view, _html} = mount(Endpoint, ThermostatView)

      assert render(view) =~ "The temp is: 1"

      GenServer.call(view.pid, {:set, :val, 1})
      GenServer.call(view.pid, {:set, :val, 2})
      GenServer.call(view.pid, {:set, :val, 3})

      assert render_click(view, :inc) =~ """
             The temp is: 4
             <button phx-click="dec">-</button>
             <button phx-click="inc">+</button>
             """

      assert render_click(view, :dec) =~ """
             The temp is: 3
             <button phx-click="dec">-</button>
             <button phx-click="inc">+</button>
             """

      assert render(view) == """
             The temp is: 3
             <button phx-click="dec">-</button>
             <button phx-click="inc">+</button>
             """
    end
  end

  describe "nested live render" do
    test "nested child render on disconnected mount" do
      {:ok, _thermo_view, html} =
        mount_disconnected(Endpoint, ThermostatView, session: %{nest: true})

      assert html =~ "The temp is: 0"
      assert html =~ "time: 12:00"
      assert html =~ "<button phx-click=\"snooze\">+</button>"
    end

    test "nested child render on connected mount" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})
      html = render(thermo_view)
      assert html =~ "The temp is: 1"
      assert html =~ "time: 12:00"
      assert html =~ "<button phx-click=\"snooze\">+</button>"

      GenServer.call(thermo_view.pid, {:set, :nest, false})
      html = render(thermo_view)
      assert html =~ "The temp is: 1"
      refute html =~ "time"
      refute html =~ "snooze"
    end

    test "dynamically added children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView)

      assert render(thermo_view) =~ "The temp is: 1"
      refute render(thermo_view) =~ "time"
      refute render(thermo_view) =~ "snooze"
      GenServer.call(thermo_view.pid, {:set, :nest, true})
      assert render(thermo_view) =~ "The temp is: 1"
      assert render(thermo_view) =~ "time"
      assert render(thermo_view) =~ "snooze"

      assert [clock_view] = children(thermo_view)
      assert [controls_view] = children(clock_view)
      assert clock_view.module == ClockView
      assert controls_view.module == ClockControlsView

      assert render_click(controls_view, :snooze) == "<button phx-click=\"snooze\">+</button>"
      assert render(clock_view) =~ "time: 12:05"
      assert render(controls_view) == "<button phx-click=\"snooze\">+</button>"
      assert render(clock_view) =~ "<button phx-click=\"snooze\">+</button>"

      :ok = GenServer.call(clock_view.pid, {:set, "12:01"})

      assert render(clock_view) =~ "time: 12:01"
      assert render(thermo_view) =~ "time: 12:01"
      assert render(thermo_view) =~ "<button phx-click=\"snooze\">+</button>"
    end

    test "nested children are removed and killed" do
      html_without_nesting = """
      The temp is: 1
      <button phx-click="dec">-</button>
      <button phx-click="inc">+</button>
      """

      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      refute render(thermo_view) == html_without_nesting

      GenServer.call(thermo_view.pid, {:set, :nest, false})

      assert_remove(clock_view, {:shutdown, :removed})
      assert_remove(controls_view, {:shutdown, :removed})

      assert render(thermo_view) == html_without_nesting
      assert children(thermo_view) == []
    end

    test "multple nested children of the same module" do
      defmodule SameChildView do
        use Phoenix.LiveView

        def render(assigns) do
          ~L"""
          <%= for name <- @names do %>
            <%= live_render(@socket, ClockView, session: %{name: name}) %>
          <% end %>
          """
        end

        def mount(_, socket) do
          {:ok, assign(socket, names: ~w(Tokyo Madrid Toronto))}
        end
      end

      {:ok, parent, _html} = mount(Endpoint, SameChildView)
      [tokyo, madrid, toronto] = children(parent)

      child_ids =
        for sess <- [tokyo, madrid, toronto],
            %{id: id} = session(sess),
            do: id

      assert Enum.uniq(child_ids) == child_ids
      assert render(parent) =~ "Tokyo"
      assert render(parent) =~ "Madrid"
      assert render(parent) =~ "Toronto"
    end

    test "parent graceful exit removes children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      stop(thermo_view)
      assert_remove(thermo_view, {:shutdown, :stop})
      assert_remove(clock_view, {:shutdown, :stop})
      assert_remove(controls_view, {:shutdown, :stop})
    end

    test "child level 1 graceful exit removes children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      stop(clock_view)
      assert_remove(clock_view, {:shutdown, :stop})
      assert_remove(controls_view, {:shutdown, :stop})
      assert children(thermo_view) == []
    end

    test "child level 2 graceful exit removes children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      stop(controls_view)
      assert_remove(controls_view, {:shutdown, :stop})
      assert children(thermo_view) == [clock_view]
      assert children(clock_view) == []
    end

    @tag :capture_log
    test "abnormal parent exit removes children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      send(thermo_view.pid, :boom)

      assert_remove(thermo_view, _)
      assert_remove(clock_view, _)
      assert_remove(controls_view, _)
    end

    @tag :capture_log
    test "abnormal child level 1 exit removes children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      send(clock_view.pid, :boom)

      assert_remove(clock_view, _)
      assert_remove(controls_view, _)
      assert children(thermo_view) == []
    end

    @tag :capture_log
    test "abnormal child level 2 exit removes children" do
      {:ok, thermo_view, _html} = mount(Endpoint, ThermostatView, session: %{nest: true})

      [clock_view] = children(thermo_view)
      [controls_view] = children(clock_view)

      send(controls_view.pid, :boom)

      assert_remove(controls_view, _)
      assert children(thermo_view) == [clock_view]
      assert children(clock_view) == []
    end

    test "nested for comprehensions" do
      users = [
        %{name: "chris", email: "chris@test"},
        %{name: "josé", email: "jose@test"}
      ]

      expected_users = "<i>chris chris@test</i>\n  \n    <i>josé jose@test</i>"

      {:ok, thermo_view, html} =
        mount(Endpoint, ThermostatView, session: %{nest: true, users: users})

      assert html =~ expected_users
      assert render(thermo_view) =~ expected_users
    end
  end

  describe "redirects" do
    test "redirect from root view on disconnected mount" do
      assert {:error, %{redirect: "/thermostat_disconnected"}} =
               mount(Endpoint, ThermostatView, session: %{redir: {:disconnected, ThermostatView}})
    end

    test "redirect from root view on connected mount" do
      assert {:error, %{redirect: "/thermostat_connected"}} =
               mount(Endpoint, ThermostatView, session: %{redir: {:connected, ThermostatView}})
    end

    test "redirect from child view on disconnected mount" do
      assert {:error, %{redirect: "/clock_disconnected"}} =
               mount(Endpoint, ThermostatView,
                 session: %{nest: true, redir: {:disconnected, ClockView}}
               )
    end

    test "redirect from child view on connected mount" do
      assert {:error, %{redirect: "/clock_connected"}} =
               mount(Endpoint, ThermostatView,
                 session: %{nest: true, redir: {:connected, ClockView}}
               )
    end

    test "redirect after connected mount from root thru sync call" do
      assert {:ok, view, _} = mount(Endpoint, ThermostatView)

      assert_redirect(view, "/path", fn ->
        assert render_click(view, :redir, "/path") == {:error, :redirect}
      end)
    end

    test "redirect after connected mount from root thru async call" do
      assert {:ok, view, _} = mount(Endpoint, ThermostatView)

      assert_redirect(view, "/async", fn ->
        send(view.pid, {:redir, "/async"})
      end)
    end
  end
end
