defmodule Elixord.Consumer do
  use Nostrum.Consumer
  # @ash_guild 711_271_361_523_351_632

  import Bitwise
  require Logger
  import Nostrum.Struct.Embed

  def handle_event({:READY, _msg, _ws_state}) do
    options = [
      %{
        name: "packages",
        type: 3,
        required: true,
        description: "A comma separated list of packages to search"
      },
      %{name: "query", type: 3, required: true, description: "What to search for on hexdocs"},
      %{
        name: "limit",
        type: 4,
        description: "The max number of results to show. Default 6.",
        min_value: 1,
        max_value: 20
      }
    ]

    Nostrum.Api.ApplicationCommand.create_global_command(%{
      name: "hexdocs",
      description: "Search hexdocs",
      options: options
    })

    Logger.info("READY")
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Nostrum.Struct.Interaction{
          data: %Nostrum.Struct.ApplicationCommandInteractionData{custom_id: "share_to_channel"},
          message: %Nostrum.Struct.Message{
            embeds: embeds
          }
        } = interaction,
        _ws_state
      }) do
    Nostrum.Api.create_interaction_response(interaction, %{
      type: 4,
      data: %{
        embeds: embeds
      }
    })

    :ok
  end

  def handle_event(
        {:INTERACTION_CREATE,
         %Nostrum.Struct.Interaction{data: %{name: name, options: options}} = interaction,
         _ws_state}
      )
      when name in ["hexdocs", "hexdocs_testing"] do
    packages =
      Enum.find(options, &(&1.name == "packages")).value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(fn package ->
        case String.split(package, "-") do
          [package] ->
            case Req.get("https://hex.pm/api/packages/#{package}",
                   headers: [{"User-Agent", "igniter-installer"}]
                 ) do
              {:ok, %{body: %{"releases" => releases} = body}} ->
                case first_non_rc_version_or_first_version(releases, body) do
                  %{"version" => version} ->
                    ["#{package}-#{version}"]

                  _ ->
                    []
                end
            end

          _ ->
            [package]
        end
      end)

    limit =
      Enum.find_value(options, 6, fn option ->
        if option.name == "limit" do
          option.value
        end
      end)
      |> min(6)

    query = Enum.find(options, &(&1.name == "query")).value

    params = %{
      q: query,
      filter_by: "package:=[#{Enum.join(packages, ",")}]",
      query_by: "title,doc"
    }

    Req.get!("https://search.hexdocs.pm/?#{URI.encode_query(params)}",
      headers: [{"User-Agent", "elixord"}]
    )
    |> Map.get(:body)
    |> Map.get("hits")
    |> Enum.uniq_by(&Map.take(&1["document"], ["title", "ref"]))
    |> Enum.take(limit)
    |> then(fn hits ->
      embed =
        %Nostrum.Struct.Embed{}
        |> put_title("Hexdocs Search Results")
        |> put_description("Searched `#{Enum.join(packages, ",")}` for `#{query}`")
        |> then(fn embed ->
          Enum.reduce(hits, embed, fn
            :split, embed ->
              put_field(
                embed,
                "\t",
                "\t"
              )

            hit, embed ->
              url = Enum.join(String.split(hit["document"]["package"], "-"), "/")

              put_field(
                embed,
                "#{hit["document"]["package"]} | #{hit["document"]["type"]}",
                "[#{split_on_space_dash(hit["document"]["title"])}](https://hexdocs.pm/#{url}/#{hit["document"]["ref"]})"
              )
          end)
        end)

      Nostrum.Api.create_interaction_response(interaction, %{
        type: 4,
        data: %{
          flags: 1 <<< 6,
          embeds: [embed],
          components: [
            Nostrum.Struct.Component.ActionRow.action_row()
            |> Nostrum.Struct.Component.ActionRow.append(
              Nostrum.Struct.Component.Button.interaction_button(
                "Share to Channel",
                "share_to_channel"
              )
            )
          ]
        }
      })
    end)
  end

  defp split_on_space_dash(text) do
    String.replace(text, " - ", "\n")
  end

  def handle_event(_other) do
    :ok
  end

  defp first_non_rc_version_or_first_version(releases, body) do
    releases = Enum.reject(releases, &body["retirements"][&1["version"]])

    Enum.find(releases, Enum.at(releases, 0), fn release ->
      !rc?(release["version"])
    end)
  end

  # This just actually checks if there is any pre-release metadata
  defp rc?(version) do
    version
    |> Version.parse!()
    |> Map.get(:pre)
    |> Enum.any?()
  end
end
