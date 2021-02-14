defmodule Ea.NoInvalidateAllInBackendError do
  defexception [:message]

  def new(backend) do
    %__MODULE__{
      message:
        "The #{backend} backend does not support invalidating the cache for all calls to the given function. You can only invalidate the cache for specific arguments."
    }
  end
end
