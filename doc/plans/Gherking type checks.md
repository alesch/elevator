This is a fundamental question in BDD. Since Gherkin is essentially a series of strings, "type safety" doesn't exist at the feature level—it only exists at the **interpretation layer** (the Step Definitions).

When we reuse generic constructs like `the elevator is ":idle"`, we face the challenge of deciding whether `:idle` refers to a `phase` or a `heading`.

Here is how we can approach type safety and data integrity while keeping steps flexible:

### 1. Explicit Gherkin (Recommended)

The most robust way to ensure type safety is to make the Gherkin itself explicit. Instead of generic steps, we use wording that maps directly to the data structure:

* `Given the phase is ":idle"`
* `Given the heading is ":idle"`

This removes ambiguity at the source. If the Gherkin is clear, the Step Definition can cast the string to the correct atom with 100% confidence.

### 2. Guarded Step Definitions

In Elixir, we can enforce type safety within the `Cabbage` step using pattern matching and guards. Even if the regex is broad, our implementation can be strict:

```elixir
defgiven ~r/is "(?<val>:[^"]+)"$/, %{val: val_str}, state do
  val = parse_atom(val_str)
  
  cond do
    val in [:idle, :moving, :arriving] -> 
      {:ok, %{state | state: %{state.state | phase: val}}}
      
    val in [:up, :down, :idle] -> 
      {:ok, %{state | state: %{state.state | heading: val}}}
      
    true -> 
      {:error, "Invalid elevator state value: #{val}"}
  end
end
```

### 3. Structural Validation (The "Step Schema")

In regular ExUnit, you manually assert types. In Cabbage, we can centralize this in our helpers. Our `parse_state_field` helper effectively acts as a **Type Transformer**.

To truly "enforce" it, we could use a schema check against our `Core` struct:

```elixir
defp set_field(state, key, value) do
  # This uses Elixir's Map.replace! to ensure the key ALREADY exists in the struct
  # Preventing the creation of ad-hoc "key-errors" or typo-fields
  %{state | key => value} 
end
```

### The Trade-off

The tension here is between **Readability** and **Rigidity**:

* **Rigid/Safe**: Lots of specific steps. Easy to code, hard to write "natural" Gherkin.
* **Flexible/Dynamic**: Fewer, smarter steps. Easy to write Gherkin, but the Step Definitions become complex "guessers" that can fail at runtime if the guessing logic is flawed (as we saw with the `KeyError :":idle"` failure).

**How would you like to balance this for the Elevator?**
Should we stick to the "Smart/Guessing" approach for `CommonSteps` but add strict validation (preventing `:":idle"` keys), or should we update the Gherkin scenarios to be more explicit about which field they are setting?
