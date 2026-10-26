// This version of the code is running using the standard BLE method rather than nimBLE 

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ADS1220_WE.h>
#include <SPI.h>

// Specific to my pin setup  
#define ADS1220_CS_PIN    18 
#define ADS1220_DRDY_PIN  17
#define SPI_SCK 36
#define SPI_MISO 37
#define SPI_MOSI 35

// BLE Structure For MATLAB
#pragma pack(push, 1)
struct {
    float data; 
    float weight;
    float force;
    uint32_t timestamp;
    uint8_t batteryLevel;
} sensorPacket;
#pragma pack(pop)

// Global variables 
ADS1220_WE ads = ADS1220_WE(ADS1220_CS_PIN, ADS1220_DRDY_PIN);
BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

float tare_offset = 0.0;
float calibration_factor_w = 3193.50; 
float calibration_factor_f = -55.4; 

// Filter variables 
const int size = 10;
float readings_array[size];
int filter_idx = 0;
float running_total = 0;

// Standard BLE Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        deviceConnected = true;
    };
    void onDisconnect(BLEServer* pServer) override {
        deviceConnected = false;
        BLEDevice::startAdvertising(); // Restart advertising when disconnected
    }
};

void setup() {
    Serial.begin(115200);

    // Initialize BLE first to prevent lockouts
    BLEDevice::init("Force_Sensor_1"); // Device name 
    BLEServer *pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // Create Service using your exact UUID
    BLEService *pService = pServer->createService("181D");

    // Create Characteristic matching your layout
    pCharacteristic = pService->createCharacteristic(
                        "2A9D",
                        BLECharacteristic::PROPERTY_READ |
                        BLECharacteristic::PROPERTY_NOTIFY
                      );

    // Add descriptor required for notifications
    pCharacteristic->addDescriptor(new BLE2902());
    pService->start();

    // Start advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID("181D");
    pAdvertising->setScanResponse(true);
    BLEDevice::startAdvertising();
    Serial.println("BLE Stack Active and Advertising!");

    // Start SPI and ADS1220
    SPI.begin(SPI_SCK, SPI_MISO, SPI_MOSI, ADS1220_CS_PIN);
    if (!ads.init()) {
        Serial.println("ADS1220 connection failed!");
        while (1);
    }

    ads.setCompareChannels(ADS1220_MUX_0_1); 
    ads.setGain(ADS1220_GAIN_128);
    ads.setVRefSource(ADS1220_VREF_AVDD_AVSS);
    ads.setVRefValue_V(3.3);
    ads.setConversionMode(ADS1220_CONTINUOUS);
    ads.setDataRate(ADS1220_DR_LVL_3);

    // Initial Tare
    Serial.println("Initial Tare... Keep sensor clear.");
    float sum = 0;
    for (int j = 0; j < 50; j++) {
        sum += ads.getVoltage_mV();
        delay(20);
    }
    tare_offset = sum / 50.0;
    Serial.print("Tare Offset Set: "); Serial.println(tare_offset, 4);
}

void loop() {
    // Check if 't' or 'T' was typed into the Serial Monitor to re-tare
    if (Serial.available() > 0) {
        char incomingChar = Serial.read();
        if (incomingChar == 't' || incomingChar == 'T') {
            Serial.println("Re-taring... Keep sensor clear.");
            float sum = 0;
            for (int j = 0; j < 50; j++) {
                sum += ads.getVoltage_mV();
                delay(20);
            }
            tare_offset = sum / 50.0;
            Serial.print("New Tare Offset Set: "); 
            Serial.println(tare_offset, 4);
        }
    }
    
    float raw_mV = ads.getVoltage_mV();

    // Running Average Filter
    running_total -= readings_array[filter_idx];
    readings_array[filter_idx] = raw_mV;
    running_total += raw_mV;
    filter_idx = (filter_idx + 1) % size;
    float average_raw = running_total / size;

    // Calculate Weight and Force values 
    float weight_g = (average_raw - tare_offset) * calibration_factor_w;
    float force_N = (average_raw - tare_offset) * calibration_factor_f;

    // BLE Update & Direct Serial Verification
    if (deviceConnected) {
        sensorPacket.data = average_raw;
        sensorPacket.weight = weight_g;
        sensorPacket.force = force_N;
        sensorPacket.timestamp = millis();
        sensorPacket.batteryLevel = 100;

        // Transmit structure over standard BLE stack
        pCharacteristic->setValue((uint8_t*)&sensorPacket, sizeof(sensorPacket));
        pCharacteristic->notify();

        Serial.print("[BLE TRANSMITTING] Force_N: "); 
        Serial.println(force_N, 3);
    }

    delay(50); 
}

