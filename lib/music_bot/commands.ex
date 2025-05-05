defmodule MusicBot.Commands do
  alias Nostrum.Api
  alias Nostrum.Struct.Embed
  require Logger

  @lyrics_api "https://api.lyrics.ovh/v1/"
  @deezer_search_api "https://api.deezer.com/search?q="
  @cover_api "https://itunes.apple.com/search"
  @artist_api "https://musicbrainz.org/ws/2/artist"
  @genre_api "https://binaryjazz.us/wp-json/genrenator/v1/genre/"
  @recommend_api "https://tastedive.com/api/similar"
  @recent_music "https://api.spotify.com/v1/browse/new-releases"
  @lastfm_api "https://ws.audioscrobbler.com/2.0"

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

    IO.inspect(url)

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
  def get_recommendations(msg, [query | rest]) do
    # Concatenar todos os elementos de 'query' em uma única string
    query_string = Enum.join([query | rest], " ")

    encoded_query = URI.encode(query_string)
    api_key = "1050254-musicbot-3C1DCF88"

    url = "#{@recommend_api}?q=#{encoded_query}&type=music&info=1&limit=10&k=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"similar" => %{"results" => results}}}
          when is_list(results) and results != [] ->
            IO.inspect(results)

            formatted =
              Enum.map(results, fn %{
                                     "name" => name,
                                     "wUrl" => wiki,
                                     "yUrl" => yt,
                                     "description" => desc
                                   } ->
                """
                🎵 **#{name}**
                📝 #{desc || "Sem descrição."}
                📖 [Wikipedia](#{wiki || "#"})
                ▶️ [YouTube](#{yt || "#"})
                """
              end)

            Api.Message.create(
              msg.channel_id,
              "**Recomendações para `#{query_string}`**:\n\n#{Enum.join(formatted, "\n\n")}"
            )

          {:ok, _} ->
            Api.Message.create(
              msg.channel_id,
              "Nenhuma recomendação encontrada para `#{query_string}`."
            )

          {:error, decode_error} ->
            Logger.error("Erro ao decodificar JSON: #{inspect(decode_error)}")
            Api.Message.create(msg.channel_id, "Erro ao processar resposta da API.")
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("API retornou erro #{code}: #{body}")
        Api.Message.create(msg.channel_id, "Erro na API (status #{code}).")

      {:error, error} ->
        Logger.error("Erro HTTP: #{inspect(error)}")
        Api.Message.create(msg.channel_id, "Erro ao buscar recomendações.")
    end
  end

  @doc """
  Gera uma playlist baseada em uma consulta usando Spotify API
  """
  def generate_recennt_musics(msg) do
    case get_spotify_token() do
      {:ok, token} ->
        IO.inspect(token)
        url = @recent_music
        headers = [{"Authorization", "Bearer #{token}"}]

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            # Decodificando o corpo da resposta
            albums_data = Jason.decode!(body)["albums"]["items"]

            # Pegando os 5 primeiros álbuns
            albums_data = Enum.take(albums_data, 5)

            response =
              Enum.map(albums_data, fn album ->
                # Extraindo as informações necessárias
                name = album["name"]
                external_url = album["external_urls"]["spotify"]
                artist = List.first(album["artists"])["name"]
                release_date = album["release_date"]

                image_url =
                  if Enum.empty?(album["images"]),
                    do: "No image available",
                    else: List.first(album["images"])["url"]

                track_count = album["total_tracks"]

                "[#{name}](#{external_url}) - Artista: #{artist} - Lançado em: #{release_date} - #{track_count} músicas\nImagem: #{image_url}"
              end)

            Api.Message.create(
              msg.channel_id,
              "**Novos lançamentos**:\n\n#{Enum.join(response, "\n\n")}"
            )

          {:ok, %HTTPoison.Response{status_code: code}} ->
            Logger.error("Erro ao buscar lançamentos: status #{code}")
            Api.Message.create(msg.channel_id, "Erro ao buscar lançamentos (status #{code})")

          {:error, error} ->
            Logger.error("Erro na requisição: #{inspect(error)}")
            Api.Message.create(msg.channel_id, "Erro ao buscar lançamentos")
        end

      {:error, _} ->
        Api.Message.create(msg.channel_id, "Erro ao autenticar com o Spotify")
    end
  end

  @doc """
  Obtém informações sobre uma música usando Songkick API
  """
  def get_song_info(msg, [artist_name, track_name]) do
    artist = URI.encode(artist_name)
    track = URI.encode(track_name)

    url = "#{@lastfm_api}/?method=track.getInfo&api_key=f6d42348e60b335cf1ea36b9ecacb8a5&artist=#{artist}&track=#{track}&format=json"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode!(body) do
          %{"track" => track_data} ->
            # Duração formatada (ms → mm:ss)
            duration =
              case Integer.parse(track_data["duration"] || "0") do
                {ms, _} ->
                  seconds = div(ms, 1000)
                  minutes = div(seconds, 60)
                  rest = rem(seconds, 60)
                  "#{minutes}:#{String.pad_leading("#{rest}", 2, "0")}"
                _ -> "Desconhecida"
              end

            # Imagem extralarge (álbum)
            image_url =
              case get_in(track_data, ["album", "image"]) do
                images when is_list(images) ->
                  case Enum.find(images, fn img -> img["size"] == "extralarge" end) do
                    %{"#text" => url} -> url
                    _ -> ""
                  end
                _ -> ""
              end

            # Tags principais (máx 3)
            tags =
              case get_in(track_data, ["toptags", "tag"]) do
                tags when is_list(tags) ->
                  tags
                  |> Enum.take(3)
                  |> Enum.map(& &1["name"])
                  |> Enum.join(", ")
                _ -> "N/A"
              end

            # Descrição (resumo truncado)
            summary =
              (track_data["wiki"]["summary"] || "")
              |> String.replace(~r/<[^>]*>/, "")
              |> String.split("Read more on Last.fm")
              |> hd()
              |> String.trim()

            embed = %Embed{
              title: "#{track_data["name"]} - #{track_data["artist"]["name"]}",
              url: track_data["url"],
              thumbnail: %{url: image_url},
              description: summary,
              fields: [
                %Embed.Field{name: "Álbum", value: track_data["album"]["title"] || "N/A", inline: true},
                %Embed.Field{name: "Ouvintes", value: track_data["listeners"], inline: true},
                %Embed.Field{name: "Reproduções", value: track_data["playcount"], inline: true},
                %Embed.Field{name: "Duração", value: duration, inline: true},
                %Embed.Field{name: "Tags", value: tags, inline: false}
              ]
            }

            Api.Message.create(msg.channel_id, embed: embed)

          _ ->
            Api.Message.create(msg.channel_id, "Música não encontrada.")
        end

      {:error, error} ->
        Logger.error("Erro na API do Last.fm: #{inspect(error)}")
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
