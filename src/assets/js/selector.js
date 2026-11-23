const vehicleData = {
  "Toyota": {
    "Camry": ["2026", "2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "Vios": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018", "2017"],
    "Innova": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018", "2017", "2016"],
    "Fortuner": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018", "2017"]
  },
  "Honda": {
    "City": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "Civic": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018", "2017"],
    "CR-V": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "Accord": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"]
  },
  "Mazda": {
    "Mazda 3": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "CX-5": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "Mazda 6": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "CX-8": ["2025", "2024", "2023", "2022", "2021", "2020", "2019"]
  },
  "Hyundai": {
    "Accent": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "SantaFe": ["2026", "2025", "2024", "2023", "2022", "2021", "2020", "2019"],
    "Tucson": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "Creta": ["2025", "2024", "2023", "2022", "2021", "2020"]
  },
  "Kia": {
    "Morning": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018", "2017", "2016"],
    "Seltos": ["2025", "2024", "2023", "2022", "2021", "2020"],
    "Cerato": ["2021", "2020", "2019", "2018"],
    "K3": ["2025", "2024", "2023", "2022"],
    "Sorento": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"]
  },
  "Ford": {
    "Ranger": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"],
    "Everest": ["2025", "2024", "2023", "2022", "2021", "2020", "2019", "2018"]
  }
};

export const VehicleSelector = {
  getBrands() {
    return Object.keys(vehicleData);
  },
  
  getModels(brand) {
    if (!vehicleData[brand]) return [];
    return Object.keys(vehicleData[brand]);
  },
  
  getYears(brand, model) {
    if (!vehicleData[brand] || !vehicleData[brand][model]) return [];
    return vehicleData[brand][model];
  },
  
  getSelectedVehicle() {
    const saved = localStorage.getItem('thamoto_selected_vehicle');
    return saved ? JSON.parse(saved) : null;
  },
  
  setSelectedVehicle(brand, model, year) {
    if (!brand || !model || !year) return;
    const vehicle = { brand, model, year };
    localStorage.setItem('thamoto_selected_vehicle', JSON.stringify(vehicle));
    // Trigger custom event so other components update if necessary
    window.dispatchEvent(new CustomEvent('vehicleChanged', { detail: vehicle }));
  },
  
  clearSelectedVehicle() {
    localStorage.removeItem('thamoto_selected_vehicle');
    window.dispatchEvent(new CustomEvent('vehicleChanged', { detail: null }));
  }
};

// Also bind to window object for legacy script tag usage if needed
window.VehicleSelector = VehicleSelector;
window.vehicleData = vehicleData;
