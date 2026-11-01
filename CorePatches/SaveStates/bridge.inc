namespace {
std::mutex state_mutex;
using StateTask = std::function<void(bool)>;
std::vector<StateTask> state_tasks;
void process_state_tasks(bool active) {
    std::vector<StateTask> tasks;
    { std::lock_guard lock(state_mutex); tasks.swap(state_tasks); }
    for (auto& task : tasks) task(active);
}
}

std::string cytrus::state_action(int action, int slot) {
    auto result = std::make_shared<std::promise<std::string>>();
    auto future = result->get_future();
    {
        std::lock_guard lock(state_mutex);
        if (!cntnr.running.load()) return "The emulation session has ended.";
        state_tasks.push_back([result, action, slot](bool active) {
            auto& system = Core::System::GetInstance();
            if (!active || !system.IsPoweredOn()) {
                result->set_value("The emulation session has ended."); return;
            }
            try {
                u64 title = 0;
                if (system.GetAppLoader().ReadProgramId(title) != Loader::ResultStatus::Success)
                    throw std::runtime_error("Could not identify this game.");
                const auto movie = system.Movie().GetCurrentMovieID();
                if (action == 0) {
                    std::string text = "OK\n";
                    for (const auto& info : Core::ListSaveStates(title, movie)) {
                        if (info.slot >= 1 && info.slot <= 3)
                            text += std::to_string(info.slot) + "|" + std::to_string(info.time) + "|" +
                                (info.status == Core::SaveStateInfo::ValidationStatus::OK ? "1" : "0") + "\n";
                    }
                    result->set_value(text); return;
                }
                if (slot < 1 || slot > 3) throw std::runtime_error("Invalid save slot.");
                if (system.Kernel().AreAsyncOperationsPending())
                    throw std::runtime_error("The game is busy. Resume briefly, then try again.");
                if (action == 1) {
                    system.SaveState(slot);
                } else if (action == 2) {
                    const auto info = Core::GetSaveStateInfo(title, movie, slot);
                    if (info.slot != static_cast<u32>(slot) || info.status != Core::SaveStateInfo::ValidationStatus::OK)
                        throw std::runtime_error("This slot is missing, damaged, or incompatible with this core version.");
                    try { system.LoadState(slot); }
                    catch (...) { cntnr.running.store(false); throw; }
                } else throw std::runtime_error("Unknown save-state operation.");
                result->set_value("OK\n");
            } catch (const std::exception& error) {
                result->set_value(error.what());
            } catch (...) {
                result->set_value("The save-state operation failed.");
            }
        });
    }
    return future.get();
}

