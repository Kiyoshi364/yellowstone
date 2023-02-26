pub fn SandboxedNoAlloc(
    comptime State: type,
    comptime Input: type,
    comptime Render: type,
) type {
    return struct {
        update: fn (State, Input) State,
        render: fn (State) Render,

        const Self = @This();

        pub fn step(
            comptime self: Self,
            state: State,
            input: Input,
        ) State {
            return self.update(state, input);
        }

        pub fn run(
            comptime self: Self,
            state: State,
            inputs: []const Input,
        ) State {
            var curr_state = state;
            return for (inputs) |input| {
                curr_state = self.step(curr_state, input);
            } else curr_state;
        }

        pub fn view(
            comptime self: Self,
            state: State,
        ) Render {
            return self.render(state);
        }
    };
}
