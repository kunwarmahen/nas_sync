import React, { useState, useEffect } from "react";
import {
  Trash2,
  Plus,
  Calendar,
  Clock,
  AlertCircle,
  CheckCircle,
  Edit2,
  X,
  Send,
  Zap,
} from "lucide-react";

// Determine API URL - smart detection for both dev and production
const getApiUrl = () => {
  // In development, process.env.REACT_APP_API_URL comes from .env file
  // In production (Docker), it will be undefined, so we auto-detect
  if (process.env.NODE_ENV === "development" && process.env.REACT_APP_API_URL) {
    console.log(
      "✓ DEV: API URL from .env file:",
      process.env.REACT_APP_API_URL
    );
    return process.env.REACT_APP_API_URL;
  }

  // In production, try config.json (created by nginx entrypoint)
  if (window.__API_URL__) {
    console.log("✓ PROD: API URL from config.json:", window.__API_URL__);
    return window.__API_URL__;
  }

  // Fall back to current hostname (works everywhere as last resort)
  const hostname = window.location.hostname;
  const port = 5000;
  const url = `http://${hostname}:${port}`;
  console.log("✓ AUTO-DETECT: API URL from hostname:", url);
  return url;
};

const DEFAULT_API_URL = getApiUrl();

export default function USBSyncDashboard() {
  const [schedules, setSchedules] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [notification, setNotification] = useState(null);
  const [usbDrives, setUsbDrives] = useState([]);
  const [systemStatus, setSystemStatus] = useState(null);
  const [testingEmail, setTestingEmail] = useState(null);
  const [testingSchedule, setTestingSchedule] = useState(null);
  const [showFolderBrowser, setShowFolderBrowser] = useState(null);
  const [folderBrowserPath, setFolderBrowserPath] = useState("/");
  const [folderBrowserHistory, setFolderBrowserHistory] = useState(["/"]);
  const [folderSearchResults, setFolderSearchResults] = useState([]);
  const [folderSearching, setFolderSearching] = useState(false);
  const [folderFilterText, setFolderFilterText] = useState("");

  // API URL state - uses smart detection
  const [apiUrl, setApiUrl] = useState(DEFAULT_API_URL);

  // In production, try to load from config.json
  useEffect(() => {
    if (process.env.NODE_ENV !== "development") {
      fetch("/config.json")
        .then((r) => r.json())
        .then((config) => {
          if (config && config.API_URL) {
            setApiUrl(config.API_URL);
            console.log(
              "✓ PROD: API URL updated from config.json:",
              config.API_URL
            );
          }
        })
        .catch((e) => {
          // Silently ignore - already using auto-detected URL
        });
    }
  }, []);

  const [formData, setFormData] = useState({
    name: "",
    usbSource: "",
    nasDestination: "",
    frequency: "weekly",
    dayOfWeek: "monday",
    dayOfMonth: "1",
    time: "02:00",
    notificationEmail: "",
    isActive: true,
  });

  useEffect(() => {
    fetchSchedules();
    fetchUSBDrives();
    fetchSystemStatus();

    // Refresh status every 30 seconds
    const interval = setInterval(() => {
      fetchSystemStatus();
      fetchSchedules();
    }, 30000);

    return () => clearInterval(interval);
  }, []);

  const fetchSchedules = async () => {
    try {
      const response = await fetch(`${apiUrl}/api/schedules`);
      const data = await response.json();
      setSchedules(data);
    } catch (error) {
      showNotification("Error loading schedules", "error");
    } finally {
      setLoading(false);
    }
  };

  const fetchUSBDrives = async () => {
    try {
      const response = await fetch(`${apiUrl}/api/usb-drives`);
      const data = await response.json();
      setUsbDrives(data);
    } catch (error) {
      console.error("Error fetching USB drives:", error);
    }
  };

  const fetchSystemStatus = async () => {
    try {
      const response = await fetch(`${apiUrl}/api/system/status`);
      const data = await response.json();
      setSystemStatus(data);
    } catch (error) {
      console.error("Error fetching system status:", error);
    }
  };

  const showNotification = (message, type = "success") => {
    setNotification({ message, type });
    setTimeout(() => setNotification(null), 4000);
  };

  const searchFolders = async (path) => {
    setFolderSearching(true);
    setFolderFilterText("");
    try {
      const response = await fetch(`${apiUrl}/api/folders/search`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path }),
      });
      const data = await response.json();
      if (data.success) {
        setFolderBrowserPath(path);
        setFolderSearchResults(data.folders);
        // Store parent path for back button
        if (data.parentPath) {
          setFolderBrowserHistory([...folderBrowserHistory.slice(0, -1), path]);
        }
      } else {
        showNotification(`Error: ${data.error}`, "error");
      }
    } catch (error) {
      showNotification("Error searching folders", "error");
    } finally {
      setFolderSearching(false);
    }
  };

  const openFolderBrowser = async (fieldType, currentPath) => {
    setShowFolderBrowser(fieldType);
    setFolderFilterText("");

    // Try to open from current path if it exists
    if (currentPath && currentPath.trim()) {
      try {
        const response = await fetch(`${apiUrl}/api/folders/search`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: currentPath }),
        });
        const data = await response.json();
        if (data.success) {
          setFolderBrowserPath(currentPath);
          setFolderBrowserHistory([currentPath]);
          setFolderSearchResults(data.folders);
          return;
        }
      } catch (error) {
        // Path doesn't exist or error, fall through to default
      }
    }

    // Fall back to root
    setFolderBrowserPath("/");
    setFolderBrowserHistory(["/"]);
    searchFolders("/");
  };

  const navigateToFolder = (folderPath) => {
    setFolderBrowserHistory([...folderBrowserHistory, folderPath]);
    searchFolders(folderPath);
  };

  const navigateBack = async () => {
    if (folderBrowserPath === "/") {
      return;
    }

    // Get parent path by removing last segment
    const parentPath =
      folderBrowserPath.substring(0, folderBrowserPath.lastIndexOf("/")) || "/";
    setFolderBrowserHistory([...folderBrowserHistory.slice(0, -1), parentPath]);
    searchFolders(parentPath);
  };

  const navigateToRoot = () => {
    setFolderBrowserHistory(["/"]);
    searchFolders("/");
  };

  const createFolder = async (path) => {
    try {
      const response = await fetch(`${apiUrl}/api/folders/create`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path }),
      });
      const data = await response.json();
      if (data.success) {
        showNotification(`Folder created: ${path}`, "success");
        searchFolders(folderBrowserPath);
      } else {
        showNotification(`Error: ${data.error}`, "error");
      }
    } catch (error) {
      showNotification("Error creating folder", "error");
    }
  };

  const testScheduleNow = async (scheduleId, scheduleName) => {
    setTestingSchedule(scheduleId);
    try {
      const response = await fetch(
        `${apiUrl}/api/schedules/${scheduleId}/test`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
        }
      );
      const data = await response.json();
      if (data.success) {
        showNotification(
          `Test started for "${scheduleName}" - Check logs and email`,
          "success"
        );
      } else {
        showNotification(`Error: ${data.error}`, "error");
      }
    } catch (error) {
      showNotification("Error starting test", "error");
    } finally {
      setTestingSchedule(null);
    }
  };

  const handleTestEmail = async (email) => {
    setTestingEmail(email);
    try {
      const response = await fetch(`${apiUrl}/api/test-email`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });

      if (!response.ok) throw new Error("Failed to send test email");

      showNotification("Test email sent! Check your inbox.", "success");
    } catch (error) {
      showNotification("Failed to send test email", "error");
    } finally {
      setTestingEmail(null);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (
      !formData.name ||
      !formData.usbSource ||
      !formData.nasDestination ||
      !formData.notificationEmail
    ) {
      showNotification("Please fill all required fields", "error");
      return;
    }

    try {
      const url = editingId
        ? `${apiUrl}/api/schedules/${editingId}`
        : `${apiUrl}/api/schedules`;
      const method = editingId ? "PUT" : "POST";

      const response = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(formData),
      });

      if (!response.ok) throw new Error("Failed to save schedule");

      showNotification(
        editingId
          ? "Schedule updated successfully"
          : "Schedule created successfully",
        "success"
      );
      resetForm();
      fetchSchedules();
    } catch (error) {
      showNotification(error.message || "Error saving schedule", "error");
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm("Are you sure you want to delete this schedule?"))
      return;

    try {
      const response = await fetch(`${apiUrl}/api/schedules/${id}`, {
        method: "DELETE",
      });
      if (!response.ok) throw new Error("Failed to delete schedule");

      showNotification("Schedule deleted successfully", "success");
      fetchSchedules();
    } catch (error) {
      showNotification(error.message || "Error deleting schedule", "error");
    }
  };

  const handleEdit = (schedule) => {
    setFormData(schedule);
    setEditingId(schedule.id);
    setShowForm(true);
  };

  const resetForm = () => {
    setFormData({
      name: "",
      usbSource: "",
      nasDestination: "",
      frequency: "weekly",
      dayOfWeek: "monday",
      dayOfMonth: "1",
      time: "02:00",
      notificationEmail: "",
      isActive: true,
    });
    setEditingId(null);
    setShowForm(false);
  };

  const getScheduleDescription = (schedule) => {
    const days = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
    ];

    if (schedule.frequency === "daily") {
      return `Daily at ${schedule.time}`;
    } else if (schedule.frequency === "weekly") {
      const dayIndex = [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
      ].indexOf(schedule.dayOfWeek.toLowerCase());
      return `Every ${days[dayIndex + 1]} at ${schedule.time}`;
    } else if (schedule.frequency === "monthly") {
      return `On day ${schedule.dayOfMonth} of month at ${schedule.time}`;
    }
  };

  const formatBytes = (bytes) => {
    if (!bytes) return "0 B";
    const k = 1024;
    const sizes = ["B", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
  };

  return (
    <div
      className="min-h-screen bg-gradient-to-br from-slate-950 via-slate-900 to-slate-800"
      style={{ fontFamily: "'Geist', system-ui" }}
    >
      {/* Header */}
      <div className="border-b border-slate-700/50 bg-slate-900/80 backdrop-blur-sm sticky top-0 z-40">
        <div className="max-w-6xl mx-auto px-6 py-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">
                USB Sync Manager
              </h1>
              <p className="text-slate-400 text-sm mt-1">
                Scheduled USB to NAS backups with email notifications
              </p>
            </div>
            <button
              onClick={() => {
                resetForm();
                setShowForm(true);
              }}
              className="flex items-center gap-2 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600 text-white px-4 py-2 rounded-lg font-medium transition-all duration-200 shadow-lg hover:shadow-xl"
            >
              <Plus size={20} /> New Schedule
            </button>
          </div>

          {/* System Status */}
          {systemStatus && (
            <div className="grid grid-cols-4 gap-4 text-sm">
              <div className="bg-slate-800/50 p-3 rounded-lg border border-slate-700">
                <div className="text-slate-500">Disk Used</div>
                <div className="text-white font-semibold">
                  {systemStatus.disk.percent.toFixed(1)}%
                </div>
              </div>
              <div className="bg-slate-800/50 p-3 rounded-lg border border-slate-700">
                <div className="text-slate-500">Memory Used</div>
                <div className="text-white font-semibold">
                  {systemStatus.memory.percent.toFixed(1)}%
                </div>
              </div>
              <div className="bg-slate-800/50 p-3 rounded-lg border border-slate-700">
                <div className="text-slate-500">Jobs Scheduled</div>
                <div className="text-white font-semibold">
                  {systemStatus.jobs_scheduled}
                </div>
              </div>
              <div className="bg-slate-800/50 p-3 rounded-lg border border-slate-700">
                <div className="text-slate-500">Total Schedules</div>
                <div className="text-white font-semibold">
                  {schedules.length}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="max-w-6xl mx-auto px-6 py-8">
        {/* Notification */}
        {notification && (
          <div
            className={`mb-6 p-4 rounded-lg flex items-center gap-3 animate-in ${
              notification.type === "success"
                ? "bg-emerald-500/10 border border-emerald-500/30 text-emerald-400"
                : "bg-red-500/10 border border-red-500/30 text-red-400"
            }`}
          >
            {notification.type === "success" ? (
              <CheckCircle size={20} />
            ) : (
              <AlertCircle size={20} />
            )}
            {notification.message}
          </div>
        )}

        {/* Form Modal */}
        {showForm && (
          <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
            <div className="bg-slate-900 rounded-xl border border-slate-700 max-w-2xl w-full shadow-2xl max-h-[90vh] overflow-y-auto">
              <div className="flex items-center justify-between p-6 border-b border-slate-700 sticky top-0 bg-slate-900">
                <h2 className="text-xl font-bold text-white">
                  {editingId ? "Edit Schedule" : "Create New Schedule"}
                </h2>
                <button
                  onClick={resetForm}
                  className="text-slate-400 hover:text-white"
                >
                  <X size={24} />
                </button>
              </div>

              <form onSubmit={handleSubmit} className="p-6 space-y-6">
                {/* Schedule Name */}
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Schedule Name *
                  </label>
                  <input
                    type="text"
                    value={formData.name}
                    onChange={(e) =>
                      setFormData({ ...formData, name: e.target.value })
                    }
                    placeholder="e.g., Documents Backup"
                    className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                  />
                </div>

                {/* Source */}
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Source Path *
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={formData.usbSource}
                      onChange={(e) =>
                        setFormData({ ...formData, usbSource: e.target.value })
                      }
                      placeholder="/media/usb/Documents"
                      className="flex-1 px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                    />
                    <button
                      type="button"
                      onClick={() =>
                        openFolderBrowser("source", formData.usbSource)
                      }
                      className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-300 hover:text-white hover:border-blue-500 transition-all"
                    >
                      Browse
                    </button>
                  </div>
                  {usbDrives.length > 0 && (
                    <div className="mt-2 text-xs text-slate-400">
                      Available USB: {usbDrives.map((d) => d.path).join(", ")}
                    </div>
                  )}
                </div>

                {/* Destination */}
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Destination Path *
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={formData.nasDestination}
                      onChange={(e) =>
                        setFormData({
                          ...formData,
                          nasDestination: e.target.value,
                        })
                      }
                      placeholder="/backups/usb-documents"
                      className="flex-1 px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                    />
                    <button
                      type="button"
                      onClick={() =>
                        openFolderBrowser(
                          "destination",
                          formData.nasDestination
                        )
                      }
                      className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-300 hover:text-white hover:border-blue-500 transition-all"
                    >
                      Browse
                    </button>
                  </div>
                </div>

                {/* Email */}
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2">
                    Notification Email *
                  </label>
                  <input
                    type="email"
                    value={formData.notificationEmail}
                    onChange={(e) =>
                      setFormData({
                        ...formData,
                        notificationEmail: e.target.value,
                      })
                    }
                    placeholder="you@example.com"
                    className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                  />
                </div>

                {/* Frequency */}
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-2">
                      Frequency
                    </label>
                    <select
                      value={formData.frequency}
                      onChange={(e) =>
                        setFormData({ ...formData, frequency: e.target.value })
                      }
                      className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                    >
                      <option value="daily">Daily</option>
                      <option value="weekly">Weekly</option>
                      <option value="monthly">Monthly</option>
                    </select>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-2">
                      Time (24h format)
                    </label>
                    <input
                      type="time"
                      value={formData.time}
                      onChange={(e) =>
                        setFormData({ ...formData, time: e.target.value })
                      }
                      className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                    />
                  </div>
                </div>

                {/* Conditional frequency options */}
                {formData.frequency === "weekly" && (
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-2">
                      Day of Week
                    </label>
                    <select
                      value={formData.dayOfWeek}
                      onChange={(e) =>
                        setFormData({ ...formData, dayOfWeek: e.target.value })
                      }
                      className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                    >
                      {[
                        "Monday",
                        "Tuesday",
                        "Wednesday",
                        "Thursday",
                        "Friday",
                        "Saturday",
                        "Sunday",
                      ].map((day) => (
                        <option key={day} value={day.toLowerCase()}>
                          {day}
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                {formData.frequency === "monthly" && (
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-2">
                      Day of Month (1-31)
                    </label>
                    <input
                      type="number"
                      min="1"
                      max="31"
                      value={formData.dayOfMonth}
                      onChange={(e) =>
                        setFormData({ ...formData, dayOfMonth: e.target.value })
                      }
                      className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
                    />
                  </div>
                )}

                {/* Active Status */}
                <div className="flex items-center gap-3">
                  <input
                    type="checkbox"
                    id="active"
                    checked={formData.isActive}
                    onChange={(e) =>
                      setFormData({ ...formData, isActive: e.target.checked })
                    }
                    className="w-4 h-4 rounded border-slate-700"
                  />
                  <label htmlFor="active" className="text-sm text-slate-300">
                    Enable this schedule
                  </label>
                </div>

                {/* Submit Buttons */}
                <div className="flex gap-3 pt-4 border-t border-slate-700">
                  <button
                    type="submit"
                    className="flex-1 bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-600 hover:to-cyan-600 text-white py-2 rounded-lg font-medium transition-all"
                  >
                    {editingId ? "Update Schedule" : "Create Schedule"}
                  </button>
                  <button
                    type="button"
                    onClick={resetForm}
                    className="flex-1 bg-slate-800 hover:bg-slate-700 text-white py-2 rounded-lg font-medium transition-all"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* Folder Browser Modal */}
        {showFolderBrowser && (
          <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
            <div className="bg-slate-900 rounded-xl border border-slate-700 max-w-2xl w-full shadow-2xl max-h-[90vh] overflow-y-auto">
              <div className="flex items-center justify-between p-6 border-b border-slate-700 sticky top-0 bg-slate-900">
                <h2 className="text-xl font-bold text-white">
                  Select{" "}
                  {showFolderBrowser === "source" ? "Source" : "Destination"}{" "}
                  Folder
                </h2>
                <button
                  onClick={() => setShowFolderBrowser(null)}
                  className="text-slate-400 hover:text-white"
                >
                  <X size={24} />
                </button>
              </div>

              <div className="p-6 space-y-4">
                {/* Breadcrumb Navigation */}
                <div className="bg-slate-800 p-3 rounded-lg border border-slate-700 text-sm">
                  <div className="text-slate-400 mb-2">Current Path:</div>
                  <div className="text-white font-mono break-all">
                    {folderBrowserPath}
                  </div>
                </div>

                {/* Navigation Buttons */}
                <div className="flex gap-2">
                  <button
                    onClick={navigateToRoot}
                    disabled={folderBrowserPath === "/"}
                    className="px-4 py-2 bg-slate-800 hover:bg-slate-700 disabled:opacity-50 text-slate-300 text-sm rounded-lg font-medium transition-all border border-slate-700"
                  >
                    ↑ Root (/)
                  </button>
                  <button
                    onClick={navigateBack}
                    disabled={folderBrowserPath === "/"}
                    className="px-4 py-2 bg-slate-800 hover:bg-slate-700 disabled:opacity-50 text-slate-300 text-sm rounded-lg font-medium transition-all border border-slate-700"
                  >
                    ← Back
                  </button>
                </div>

                {/* Create New Folder */}
                <div className="flex gap-2">
                  <input
                    type="text"
                    placeholder="New folder name..."
                    id="newFolderName"
                    className="flex-1 px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-blue-500"
                  />
                  <button
                    onClick={() => {
                      const name =
                        document.getElementById("newFolderName").value;
                      if (name) {
                        const newPath =
                          folderBrowserPath === "/"
                            ? `/${name}`
                            : `${folderBrowserPath}/${name}`;
                        createFolder(newPath);
                        document.getElementById("newFolderName").value = "";
                      }
                    }}
                    className="px-6 py-2 bg-emerald-500 hover:bg-emerald-600 text-white rounded-lg font-medium"
                  >
                    + Create
                  </button>
                </div>

                {/* Filter Input */}
                <div>
                  <input
                    type="text"
                    placeholder="Type to filter folders..."
                    value={folderFilterText}
                    onChange={(e) => setFolderFilterText(e.target.value)}
                    autoFocus
                    className="w-full px-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:border-blue-500"
                  />
                </div>

                {/* Folders List - Drill Down */}
                <div className="border border-slate-700 rounded-lg p-4 max-h-[400px] overflow-y-auto">
                  {folderSearching ? (
                    <div className="text-center py-8 text-slate-400">
                      Searching...
                    </div>
                  ) : folderSearchResults.filter(
                      (f) =>
                        folderFilterText === "" ||
                        f.name
                          .toLowerCase()
                          .includes(folderFilterText.toLowerCase())
                    ).length === 0 ? (
                    <div className="text-center py-8 text-slate-400">
                      {folderSearchResults.length === 0
                        ? folderBrowserPath === "/"
                          ? "No folders in root"
                          : "No folders here"
                        : "No folders match your filter"}
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {folderSearchResults
                        .filter(
                          (f) =>
                            folderFilterText === "" ||
                            f.name
                              .toLowerCase()
                              .includes(folderFilterText.toLowerCase())
                        )
                        .map((folder, idx) => (
                          <div key={idx} className="space-y-1">
                            <button
                              onClick={() => navigateToFolder(folder.path)}
                              disabled={folder.restricted}
                              className={`w-full text-left p-3 rounded border transition-all ${
                                folder.restricted
                                  ? "bg-slate-900 border-slate-700 text-slate-600 cursor-not-allowed"
                                  : "bg-slate-800 hover:bg-slate-700 border-slate-700 hover:border-blue-500 text-white cursor-pointer"
                              }`}
                            >
                              <div className="flex items-center gap-2">
                                <span className="text-lg">📁</span>
                                <span className="font-medium flex-1">
                                  {folder.name}
                                </span>
                                <span className="text-xs text-slate-500">
                                  →
                                </span>
                              </div>
                            </button>
                            {!folder.restricted && (
                              <button
                                onClick={() => {
                                  if (showFolderBrowser === "source") {
                                    setFormData({
                                      ...formData,
                                      usbSource: folder.path,
                                    });
                                  } else {
                                    setFormData({
                                      ...formData,
                                      nasDestination: folder.path,
                                    });
                                  }
                                  setShowFolderBrowser(null);
                                }}
                                className="w-full text-left px-3 py-1 text-sm bg-slate-700/50 hover:bg-blue-500/20 text-blue-400 hover:text-blue-300 rounded border border-slate-700 transition-all ml-6"
                              >
                                ✓ Select this folder
                              </button>
                            )}
                          </div>
                        ))}
                    </div>
                  )}
                </div>

                {/* Buttons */}
                <div className="flex gap-3 pt-4 border-t border-slate-700">
                  <button
                    onClick={() => setShowFolderBrowser(null)}
                    className="flex-1 bg-slate-800 hover:bg-slate-700 text-white py-2 rounded-lg font-medium"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
        {loading ? (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-400"></div>
            <p className="text-slate-400 mt-4">Loading schedules...</p>
          </div>
        ) : schedules.length === 0 ? (
          <div className="text-center py-12 border-2 border-dashed border-slate-700 rounded-lg">
            <Calendar size={48} className="mx-auto text-slate-600 mb-4" />
            <p className="text-slate-400 text-lg">No schedules yet</p>
            <p className="text-slate-500 text-sm mt-1">
              Create your first backup schedule to get started
            </p>
          </div>
        ) : (
          <div className="grid gap-4">
            {schedules.map((schedule) => (
              <div
                key={schedule.id}
                className="group bg-gradient-to-br from-slate-800/60 to-slate-800/30 border border-slate-700 hover:border-slate-600 rounded-xl p-6 transition-all duration-300 hover:shadow-lg hover:shadow-blue-500/10"
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-2">
                      <h3 className="text-lg font-bold text-white">
                        {schedule.name}
                      </h3>
                      <span
                        className={`px-3 py-1 rounded-full text-xs font-medium ${
                          schedule.isActive
                            ? "bg-emerald-500/20 text-emerald-400 border border-emerald-500/30"
                            : "bg-slate-700/50 text-slate-400 border border-slate-600"
                        }`}
                      >
                        {schedule.isActive ? "Active" : "Inactive"}
                      </span>
                    </div>

                    <div className="space-y-2 text-sm">
                      <div className="text-slate-400">
                        <span className="text-slate-500">From:</span>{" "}
                        <code className="text-cyan-400 bg-black/30 px-2 py-1 rounded text-xs">
                          {schedule.usbSource}
                        </code>
                      </div>
                      <div className="text-slate-400">
                        <span className="text-slate-500">To:</span>{" "}
                        <code className="text-cyan-400 bg-black/30 px-2 py-1 rounded text-xs">
                          {schedule.nasDestination}
                        </code>
                      </div>
                      <div className="flex items-center gap-2 text-slate-400 mt-3">
                        <Clock size={16} className="text-slate-600" />
                        {getScheduleDescription(schedule)}
                      </div>
                      <div className="text-slate-500 text-xs mt-2">
                        Email: {schedule.notificationEmail}
                      </div>
                    </div>
                  </div>

                  <div className="flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={() =>
                        testScheduleNow(schedule.id, schedule.name)
                      }
                      disabled={testingSchedule === schedule.id}
                      className="p-2 rounded-lg bg-amber-500/20 text-amber-400 hover:bg-amber-500/30 transition-all disabled:opacity-50"
                      title="Test now"
                    >
                      <Zap size={18} />
                    </button>
                    <button
                      onClick={() =>
                        handleTestEmail(schedule.notificationEmail)
                      }
                      disabled={testingEmail === schedule.notificationEmail}
                      className="p-2 rounded-lg bg-green-500/20 text-green-400 hover:bg-green-500/30 transition-all disabled:opacity-50"
                      title="Send test email"
                    >
                      <Send size={18} />
                    </button>
                    <button
                      onClick={() => handleEdit(schedule)}
                      className="p-2 rounded-lg bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-all"
                      title="Edit schedule"
                    >
                      <Edit2 size={18} />
                    </button>
                    <button
                      onClick={() => handleDelete(schedule.id)}
                      className="p-2 rounded-lg bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-all"
                      title="Delete schedule"
                    >
                      <Trash2 size={18} />
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
