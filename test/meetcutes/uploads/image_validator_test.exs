defmodule Meetcutes.Uploads.ImageValidatorTest do
  use ExUnit.Case, async: true

  alias Meetcutes.Uploads.ImageValidator

  test "streams SHA-256 in chunks and matches the full-file digest" do
    contents = :crypto.strong_rand_bytes(2_500_000)

    path =
      Path.join(
        System.tmp_dir!(),
        "meetcutes_hash_#{System.unique_integer([:positive])}.bin"
      )

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    upload = %Plug.Upload{
      path: path,
      filename: "photo.png",
      content_type: "image/png"
    }

    assert {:ok, digest} = ImageValidator.sha256(upload)

    expected =
      :crypto.hash(:sha256, contents)
      |> Base.encode16(case: :lower)

    assert digest == expected
  end

  test "returns a validation error when the upload path is missing" do
    upload = %Plug.Upload{
      path: Path.join(System.tmp_dir!(), "missing-hash-source.bin"),
      filename: "missing.png",
      content_type: "image/png"
    }

    assert {:error, :invalid_image} = ImageValidator.sha256(upload)
  end
end
