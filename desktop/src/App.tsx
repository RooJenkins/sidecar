import { useState } from "react";
import Sidebar from "./components/Sidebar";
import ScanPage from "./pages/ScanPage";
import SearchPage from "./pages/SearchPage";
import StatusPage from "./pages/StatusPage";
import SettingsPage from "./pages/SettingsPage";

export default function App() {
  const [activePage, setActivePage] = useState("scan");
  const [folderPath, setFolderPath] = useState("");

  return (
    <div className="flex h-screen bg-[var(--bg-primary)]">
      <Sidebar
        activePage={activePage}
        onNavigate={setActivePage}
        folderPath={folderPath}
      />

      <main className="flex-1 flex flex-col overflow-hidden">
        {activePage === "scan" && (
          <ScanPage folderPath={folderPath} onFolderSelect={setFolderPath} />
        )}
        {activePage === "search" && <SearchPage folderPath={folderPath} />}
        {activePage === "status" && <StatusPage folderPath={folderPath} />}
        {activePage === "settings" && <SettingsPage folderPath={folderPath} />}
      </main>
    </div>
  );
}
