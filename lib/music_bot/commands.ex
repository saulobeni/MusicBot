defmodule MusicBot.Commands do
  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  require Logger

  @lyrics_api "https://api.lyrics.ovh/v1/"
  @deezer_search_api "https://api.deezer.com/search?q="
  @cover_api "https://itunes.apple.com/search"

  @artist_api "https://musicbrainz.org/ws/2/artist/"
  @recommend_api "https://api.deezer.com/radio/%s"
  @song_api "https://api.songkick.com/api/3.0/search/artists.json"
  @genre_api "https://binaryjazz.us/wp-json/genrenator/v1/genre/"

  @spec get_spotify_token() :: {:error, :token_error} | {:ok, any()}
  def get_spotify_token() do
    url = "https://accounts.spotify.com/api/token"
    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    body =
      URI.encode_query(%{
        "grant_type" => "client_credentials",
        "client_id" => "de587952ba984c148ada91d68cdd4cad",
        "client_secret" => "285e4facbc7043e6bedf033be3af0452"
      })

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        token = Jason.decode!(body)["access_token"]
        {:ok, token}

      {:error, error} ->
        Logger.error("Erro ao obter token do Spotify: #{inspect(error)}")
        {:error, :token_error}
    end
  end

  @doc """
  Busca letras de música usando a API Lyrics.ovh
  """
  def get_lyrics(msg, [artist | song]) do
    # Codifica separadamente o nome do artista e o nome da música
    artist = URI.encode(artist)
    song = Enum.join(song, " ") |> URI.encode()

    # Monta a URL com a codificação correta
    url = "#{@lyrics_api}#{artist}/#{song}"

    IO.inspect(url)

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        lyrics = Jason.decode!(body)["lyrics"]

        # Mostra a letra da música até um máximo de 1500 caracteres
        Api.Message.create(
          msg.channel_id,
          "**#{song} - #{artist}**\n\n#{String.slice(lyrics, 0..1500)}..."
        )

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Api.Message.create(
          msg.channel_id,
          "Letra não encontrada para #{song} de #{artist}, a estrutura do comando deve ser !lyrics 'ARTISTA' 'NOME DA MUSICA'"
        )

      {:error, error} ->
        Logger.error("Lyrics API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar letra")
    end
  end

  @doc """
  Obtém informações sobre um artista usando TheAudioDB API
  """
  def get_artist_info(msg, name_parts) do
    artist_name = Enum.join(name_parts, " ") |> URI.encode()
    url = "#{@artist_api}?query=#{artist_name}&fmt=json"

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        %{"artists" => artists} = Jason.decode!(body)

        IO.inspect(artists)

        case List.first(artists) do
          nil ->
            Api.Message.create(msg.channel_id, "Artista não encontrado.")

          artist ->
            # Informações principais
            name = artist["name"] || "Desconhecido"
            country = artist["country"] || "N/A"
            gender = artist["gender"] || "N/A"
            disambiguation = artist["disambiguation"] || "Nenhuma descrição"

            # Ano de início (nasce em 1972, por exemplo)
            year =
              artist["life-span"]["begin"]
              |> case do
                nil -> "N/A"
                date -> String.slice(date, 0..3)
              end

            # Alias do artista
            aliases =
              artist["aliases"]
              |> Enum.map(& &1["name"])
              |> Enum.uniq()
              |> Enum.take(5)
              |> Enum.join(", ")
              |> case do
                "" -> "Nenhum"
                list -> list
              end

            # País de origem (da área do artista)
            area_name = artist["area"]["name"] || "N/A"

            # Tags
            tags =
              artist["tags"]
              |> Enum.sort_by(& &1["count"], :desc)
              |> Enum.take(5)
              |> Enum.map(& &1["name"])
              |> Enum.join(", ")
              |> case do
                "" -> "Nenhum"
                list -> list
              end

            # Criação do embed
            embed = %{
              title: name,
              description: disambiguation,
              fields: [
                %{name: "País", value: country, inline: true},
                %{name: "Gênero", value: gender, inline: true},
                %{name: "Ano de início", value: year, inline: true},
                %{name: "Apelidos", value: aliases, inline: false},
                %{name: "Tags", value: tags, inline: false},
                %{name: "Área", value: area_name, inline: true}
              ]
            }

            Api.Message.create(msg.channel_id, %{embed: embed})
        end

      {:error, error} ->
        Logger.error("Erro na API do MusicBrainz: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar artista.")
    end
  end


  @doc """
  Obtém recomendações de música baseadas em um artista/gênero usando Deezer API
  """
  def get_recommendations(msg, [query]) do
    query = URI.encode(query)

    case HTTPoison.get("#{@recommend_api}#{query}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)

        tracks =
          Enum.map(data["data"], fn track ->
            "#{track["title"]} - #{track["artist"]["name"]}"
          end)

        Api.Message.create(
          msg.channel_id,
          "**Recomendações para #{query}**:\n\n#{Enum.join(tracks, "\n")}"
        )

      {:error, error} ->
        Logger.error("Recommendation API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar recomendações")
    end
  end

  @doc """
  Gera uma playlist baseada em uma consulta usando Spotify API
  """
 def generate_playlist(msg, [category]) do
  case get_spotify_token() do
    {:ok, token} ->
      category = URI.encode(category)
      url = "https://api.spotify.com/v1/browse/categories/#{category}/playlists"
      headers = [{"Authorization", "Bearer #{token}"}]

      case HTTPoison.get(url, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          # Decodificando o corpo da resposta
          playlists_data = Jason.decode!(body)["playlists"]["items"]

          response =
            Enum.map(playlists_data, fn playlist ->
              # Para cada playlist, extraímos as informações de nome, URL e número de faixas
              name = playlist["name"]
              external_url = playlist["external_urls"]["spotify"]
              track_count = playlist["tracks"]["total"]
              image_url = List.first(playlist["images"])["url"] || "No image available"

              "[#{name}](#{external_url}) - #{track_count} músicas\nImagem: #{image_url}"
            end)

          Api.Message.create(
            msg.channel_id,
            "**Playlists encontradas para a categoria #{category}**:\n\n#{Enum.join(response, "\n\n")}"
          )

        {:ok, %HTTPoison.Response{status_code: code}} ->
          Logger.error("Erro ao buscar playlists: status #{code}")
          Api.Message.create(msg.channel_id, "Erro ao buscar playlists (status #{code})")

        {:error, error} ->
          Logger.error("Erro na requisição: #{inspect(error)}")
          Api.Message.create(msg.channel_id, "Erro ao buscar playlists")
      end

    {:error, _} ->
      Api.Message.create(msg.channel_id, "Erro ao autenticar com o Spotify")
  end
end




  @doc """
  Obtém informações sobre uma música usando Songkick API
  """
  def get_song_info(msg, [song]) do
    song = URI.encode(song)

    case HTTPoison.get("#{@song_api}?query=#{song}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)["resultsPage"]["results"]["artist"] |> List.first()

        embed = %Embed{
          title: data["displayName"],
          url: data["uri"],
          fields: [
            %Embed.Field{name: "Seguidores", value: data["stats"]["followers"], inline: true},
            %Embed.Field{name: "Eventos", value: data["stats"]["eventCount"], inline: true}
          ]
        }

        Api.Message.create(msg.channel_id, embed: embed)

      {:error, error} ->
        Logger.error("Song API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar informações da música")
    end
  end

  @doc """
  Gera um gênero musical aleatório usando Genrenator API
  """
  def get_genre_info(msg, _args) do
    case HTTPoison.get(@genre_api) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        genre = Jason.decode!(body)
        Api.Message.create(msg.channel_id, "**Gênero musical aleatório**: #{genre}")

      {:error, error} ->
        Logger.error("Genre API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao gerar gênero musical")
    end
  end

  @doc """
  Obtém a capa de um álbum usando iTunes API
  """
  def get_album_cover(msg, [artist, album]) do
    artist = URI.encode(artist)
    album = URI.encode(album)

    case HTTPoison.get("#{@cover_api}?term=#{artist}+#{album}&entity=album&limit=1") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => [data | _]}} when is_map(data) ->
            embed = %Embed{
              title: "#{data["collectionName"]} - #{data["artistName"]}",
              image: %Embed.Image{
                url: String.replace(data["artworkUrl100"], "100x100bb.jpg", "500x500bb.jpg")
              }
            }

            Api.Message.create(msg.channel_id, embed: embed)

          _ ->
            Api.Message.create(msg.channel_id, "Álbum não encontrado ou resposta inválida.")
        end

      {:error, error} ->
        Logger.error("Cover API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar capa do álbum")
    end
  end


  @doc """
  Busca músicas pelo nome ou artista usando a API do Deezer
  """
  def search_song(msg, content) do
    full_query =
      content
      |> Enum.join(" ")
      |> URI.encode()

    url = "#{@deezer_search_api}#{full_query}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{body: body}} ->
        {:ok, json} = Jason.decode(body)

        IO.inspect(body)

        songs = json["data"] |> Enum.take(5)

        results =
          Enum.map(songs, fn song ->
            title = song["title"]
            artist = song["artist"]["name"]
            link = song["link"]
            album = song["album"]["title"]
            album_cover = song["album"]["cover_medium"]
            artist_link = song["artist"]["link"]

            """
            **#{title}** - [#{artist}](#{artist_link})
            Álbum: #{album}
            [Ouvir música](#{link})
            Imagem do Álbum: ![#{album}](#{album_cover})
            """
          end)

        Api.Message.create(
          msg.channel_id,
          "**Resultados da busca por `#{URI.decode(full_query)}`:**\n\n#{Enum.join(results, "\n\n")}"
        )

      {:error, error} ->
        Logger.error("Search Song API error: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar músicas")
    end
  end
end
