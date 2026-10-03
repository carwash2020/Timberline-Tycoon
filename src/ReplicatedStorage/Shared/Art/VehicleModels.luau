--!strict
-- Vehicle meshes. Each role uses the individual piece meshId
-- (not the Assembly Model's mesh) at the Assembly or ByTruck size.
-- ScoutATV has no bed and no hitch. Trailer hitch width follows the tow truck.
-- Triangle budget for a truck plus its trailer: 12,000 (not measured here).

local VehicleModels = {}

export type Piece = { meshId: number, size: Vector3 }

local trucks: { [string]: { [string]: Piece } } = {
	Rustbucket = {
		Body = { meshId = 120725616537680, size = Vector3.new(10.64, 8.8, 23.409) },
		Glass = { meshId = 135044303797643, size = Vector3.new(9.863, 3.186, 3.698) },
		Lights = { meshId = 124493769904792, size = Vector3.new(8.437, 0.802, 20.568) },
		Bed = { meshId = 120734733805977, size = Vector3.new(8.4, 3.02, 13.977) },
		Wheel = { meshId = 139390483847560, size = Vector3.new(1.308, 3.372, 3.372) },
		Hitch = { meshId = 99956936383854, size = Vector3.new(0.7, 1.06, 1.68) },
	},
	Pickup = {
		Body = { meshId = 110946981942122, size = Vector3.new(11.11, 9.145, 26.136) },
		Glass = { meshId = 76718452145232, size = Vector3.new(10.098, 3.391, 3.395) },
		Lights = { meshId = 100056308278514, size = Vector3.new(8.54, 2.95, 25.03) },
		Bed = { meshId = 137659811327372, size = Vector3.new(8.72, 3.87, 15.685) },
		Wheel = { meshId = 124886704209701, size = Vector3.new(1.373, 3.509, 3.509) },
		Hitch = { meshId = 121507994255438, size = Vector3.new(0.7, 1.06, 1.68) },
	},
	ScoutATV = {
		Body = { meshId = 131883902524854, size = Vector3.new(9.3, 9.36, 12.891) },
		Glass = { meshId = 93031171745389, size = Vector3.new(1.4, 0.867, 0.308) },
		Lights = { meshId = 117328552905839, size = Vector3.new(9.4, 2.648, 10.999) },
		Wheel = { meshId = 140001053768737, size = Vector3.new(1.82, 3.245, 3.203) },
	},
	Flatbed = {
		Body = { meshId = 101615123184878, size = Vector3.new(12.14, 10.918, 34.425) },
		Glass = { meshId = 98760659539151, size = Vector3.new(11.2, 3.947, 3.852) },
		Lights = { meshId = 111333312069489, size = Vector3.new(7.96, 8.76, 33.76) },
		Bed = { meshId = 139734928087096, size = Vector3.new(9.76, 7.475, 23.4) },
		Wheel = { meshId = 131955977341353, size = Vector3.new(1.43, 3.638, 3.638) },
		Hitch = { meshId = 140349480773545, size = Vector3.new(0.7, 1.06, 1.68) },
	},
	LoggingRig = {
		Body = { meshId = 106201918511427, size = Vector3.new(12.91, 14.281, 46.67) },
		Glass = { meshId = 110663013657387, size = Vector3.new(12.194, 4.44, 3.925) },
		Lights = { meshId = 82098165138477, size = Vector3.new(11.865, 9.605, 45.8) },
		Bed = { meshId = 124435372710468, size = Vector3.new(10.67, 7.325, 33.8) },
		Wheel = { meshId = 81542757402029, size = Vector3.new(1.495, 4.548, 4.548) },
		Hitch = { meshId = 103819640831326, size = Vector3.new(0.7, 1.06, 1.68) },
	},
}

local trailers: { [string]: { [string]: { [string]: Piece } } } = {
	PonyTrailer = {
		Default = {
			Body = { meshId = 107003020182290, size = Vector3.new(9.79, 2.035, 13.045) },
			Lights = { meshId = 88163132342304, size = Vector3.new(8.2, 0.38, 12.83) },
			Bed = { meshId = 90389536788385, size = Vector3.new(8.34, 2.14, 13.0) },
			Wheel = { meshId = 109498505023571, size = Vector3.new(1.113, 2.988, 2.937) },
			Hitch = { meshId = 139471072919132, size = Vector3.new(6.466, 3.51, 3.063) },
		},
		Flatbed = {
			Body = { meshId = 107003020182290, size = Vector3.new(11.09, 2.035, 13.045) },
			Lights = { meshId = 88163132342304, size = Vector3.new(9.5, 0.38, 12.83) },
			Bed = { meshId = 90389536788385, size = Vector3.new(9.64, 2.14, 13.0) },
			Wheel = { meshId = 109498505023571, size = Vector3.new(1.113, 2.988, 2.937) },
			Hitch = { meshId = 139471072919132, size = Vector3.new(7.739, 3.51, 3.072) },
		},
		LoggingRig = {
			Body = { meshId = 107003020182290, size = Vector3.new(11.87, 2.035, 13.045) },
			Lights = { meshId = 88163132342304, size = Vector3.new(10.28, 0.38, 12.83) },
			Bed = { meshId = 90389536788385, size = Vector3.new(10.42, 2.14, 13.0) },
			Wheel = { meshId = 109498505023571, size = Vector3.new(1.113, 2.988, 2.937) },
			Hitch = { meshId = 139471072919132, size = Vector3.new(8.505, 3.51, 3.076) },
		},
		Pickup = {
			Body = { meshId = 107003020182290, size = Vector3.new(10.31, 2.035, 13.045) },
			Lights = { meshId = 88163132342304, size = Vector3.new(8.72, 0.38, 12.83) },
			Bed = { meshId = 90389536788385, size = Vector3.new(8.86, 2.14, 13.0) },
			Wheel = { meshId = 109498505023571, size = Vector3.new(1.113, 2.988, 2.937) },
			Hitch = { meshId = 139471072919132, size = Vector3.new(6.974, 3.51, 3.067) },
		},
		Rustbucket = {
			Body = { meshId = 107003020182290, size = Vector3.new(9.79, 2.035, 13.045) },
			Lights = { meshId = 88163132342304, size = Vector3.new(8.2, 0.38, 12.83) },
			Bed = { meshId = 90389536788385, size = Vector3.new(8.34, 2.14, 13.0) },
			Wheel = { meshId = 109498505023571, size = Vector3.new(1.113, 2.988, 2.937) },
			Hitch = { meshId = 139471072919132, size = Vector3.new(6.466, 3.51, 3.063) },
		},
	},
	RanchTrailer = {
		Default = {
			Body = { meshId = 101057277743396, size = Vector3.new(10.31, 2.1, 18.245) },
			Lights = { meshId = 97749142571629, size = Vector3.new(8.72, 4.22, 18.295) },
			Bed = { meshId = 105565294587502, size = Vector3.new(8.88, 4.13, 18.27) },
			Wheel = { meshId = 131671997531071, size = Vector3.new(1.113, 3.118, 3.065) },
			Hitch = { meshId = 124380880700146, size = Vector3.new(6.974, 3.51, 3.067) },
		},
		Flatbed = {
			Body = { meshId = 101057277743396, size = Vector3.new(11.09, 2.1, 18.245) },
			Lights = { meshId = 97749142571629, size = Vector3.new(9.5, 4.22, 18.295) },
			Bed = { meshId = 105565294587502, size = Vector3.new(9.66, 4.13, 18.27) },
			Wheel = { meshId = 131671997531071, size = Vector3.new(1.113, 3.118, 3.065) },
			Hitch = { meshId = 124380880700146, size = Vector3.new(7.739, 3.51, 3.072) },
		},
		LoggingRig = {
			Body = { meshId = 101057277743396, size = Vector3.new(11.87, 2.1, 18.245) },
			Lights = { meshId = 97749142571629, size = Vector3.new(10.28, 4.22, 18.295) },
			Bed = { meshId = 105565294587502, size = Vector3.new(10.44, 4.13, 18.27) },
			Wheel = { meshId = 131671997531071, size = Vector3.new(1.113, 3.118, 3.065) },
			Hitch = { meshId = 124380880700146, size = Vector3.new(8.505, 3.51, 3.076) },
		},
		Pickup = {
			Body = { meshId = 101057277743396, size = Vector3.new(10.31, 2.1, 18.245) },
			Lights = { meshId = 97749142571629, size = Vector3.new(8.72, 4.22, 18.295) },
			Bed = { meshId = 105565294587502, size = Vector3.new(8.88, 4.13, 18.27) },
			Wheel = { meshId = 131671997531071, size = Vector3.new(1.113, 3.118, 3.065) },
			Hitch = { meshId = 124380880700146, size = Vector3.new(6.974, 3.51, 3.067) },
		},
		Rustbucket = {
			Body = { meshId = 101057277743396, size = Vector3.new(9.79, 2.1, 18.245) },
			Lights = { meshId = 97749142571629, size = Vector3.new(8.2, 4.22, 18.295) },
			Bed = { meshId = 105565294587502, size = Vector3.new(8.36, 4.13, 18.27) },
			Wheel = { meshId = 131671997531071, size = Vector3.new(1.113, 3.118, 3.065) },
			Hitch = { meshId = 124380880700146, size = Vector3.new(6.466, 3.51, 3.063) },
		},
	},
	HeavyHauler = {
		Default = {
			Body = { meshId = 93977628567245, size = Vector3.new(12.0, 2.085, 26.045) },
			Lights = { meshId = 90030662798643, size = Vector3.new(10.28, 4.22, 26.075) },
			Bed = { meshId = 108656014869417, size = Vector3.new(10.46, 4.15, 26.08) },
			Wheel = { meshId = 81074969756089, size = Vector3.new(1.178, 3.248, 3.192) },
			Hitch = { meshId = 128380567399095, size = Vector3.new(8.505, 3.51, 3.076) },
		},
		Flatbed = {
			Body = { meshId = 93977628567245, size = Vector3.new(11.22, 2.085, 26.045) },
			Lights = { meshId = 90030662798643, size = Vector3.new(9.5, 4.22, 26.075) },
			Bed = { meshId = 108656014869417, size = Vector3.new(9.68, 4.15, 26.08) },
			Wheel = { meshId = 81074969756089, size = Vector3.new(1.178, 3.248, 3.192) },
			Hitch = { meshId = 128380567399095, size = Vector3.new(7.739, 3.51, 3.072) },
		},
		LoggingRig = {
			Body = { meshId = 93977628567245, size = Vector3.new(12.0, 2.085, 26.045) },
			Lights = { meshId = 90030662798643, size = Vector3.new(10.28, 4.22, 26.075) },
			Bed = { meshId = 108656014869417, size = Vector3.new(10.46, 4.15, 26.08) },
			Wheel = { meshId = 81074969756089, size = Vector3.new(1.178, 3.248, 3.192) },
			Hitch = { meshId = 128380567399095, size = Vector3.new(8.505, 3.51, 3.076) },
		},
		Pickup = {
			Body = { meshId = 93977628567245, size = Vector3.new(10.44, 2.085, 26.045) },
			Lights = { meshId = 90030662798643, size = Vector3.new(8.72, 4.22, 26.075) },
			Bed = { meshId = 108656014869417, size = Vector3.new(8.9, 4.15, 26.08) },
			Wheel = { meshId = 81074969756089, size = Vector3.new(1.178, 3.248, 3.192) },
			Hitch = { meshId = 128380567399095, size = Vector3.new(6.974, 3.51, 3.067) },
		},
		Rustbucket = {
			Body = { meshId = 93977628567245, size = Vector3.new(9.92, 2.085, 26.045) },
			Lights = { meshId = 90030662798643, size = Vector3.new(8.2, 4.22, 26.075) },
			Bed = { meshId = 108656014869417, size = Vector3.new(8.38, 4.15, 26.08) },
			Wheel = { meshId = 81074969756089, size = Vector3.new(1.178, 3.248, 3.192) },
			Hitch = { meshId = 128380567399095, size = Vector3.new(6.466, 3.51, 3.063) },
		},
	},
}

function VehicleModels.Truck(id: string): { [string]: Piece }?
	return trucks[id]
end

function VehicleModels.Trailer(id: string, truckId: string?): { [string]: Piece }?
	local entry = trailers[id]
	if not entry then
		return nil
	end
	if truckId and entry[truckId] then
		return entry[truckId]
	end
	return entry.Default
end

return VehicleModels
