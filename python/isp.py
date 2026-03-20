# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import os

os.environ["OPENCV_IO_ENABLE_OPENEXR"] = "1"
import math

import cv2 as cv2
import numpy as np


def colorgain(
    cfa: np.ndarray,
    rgain: float = 1.0,
    bgain: float = 1.0,
    g0gain: float = 1.0,
    g1gain: float = 1.0,
    code: int = cv2.COLOR_BayerBGGR2BGR,
):
    h = cfa.shape[0]
    w = cfa.shape[1]

    # default: COLOR_BayerBGGR2BGR
    b_y = 0
    b_x = 0
    g0_y = 0
    g0_x = 1
    g1_y = 1
    g1_x = 0
    r_y = 1
    r_x = 1

    if code == cv2.COLOR_BayerGBRG2BGR:
        g0_y = 0
        g0_x = 0
        b_y = 0
        b_x = 1
        r_y = 1
        r_x = 0
        g1_y = 1
        g1_x = 1

    elif code == cv2.COLOR_BayerGRBG2BGR:
        g0_y = 0
        g0_x = 0
        r_y = 0
        r_x = 1
        b_y = 1
        b_x = 0
        g1_y = 1
        g1_x = 1

    elif code == cv2.COLOR_BayerRGGB2BGR:
        g0_y = 0
        g0_x = 1
        g1_y = 1
        g1_x = 0
        r_y = 0
        r_x = 0
        b_y = 1
        b_x = 1

    # loop over the image
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            cfa[y + r_y, x + r_x] *= rgain
            cfa[y + g0_y, x + g0_x] *= g0gain
            cfa[y + g1_y, x + g1_x] *= g1gain
            cfa[y + b_y, x + b_x] *= bgain

    return cfa


def rgb_to_ycocgr(img: np.ndarray):
    h = img.shape[0]
    w = img.shape[1]

    out = np.zeros(shape=img.shape, dtype=np.int32)
    img = img.astype(np.int32)

    # loop over the image
    for y in range(0, h):
        for x in range(0, w):
            # Co  = R - B;
            out[y, x, 1] = img[y, x, 2] - img[y, x, 0]

            # tmp = B + Co/2;
            tmp = img[y, x, 0] + (out[y, x, 1] >> 1)

            # Cg  = G - tmp;
            out[y, x, 2] = img[y, x, 1] - tmp

            # Y   = tmp + Cg/2;
            out[y, x, 0] = tmp + (out[y, x, 2] >> 1)

    return out


def ycocg_to_rgbr(img: np.ndarray):
    h = img.shape[0]
    w = img.shape[1]

    out = np.zeros(shape=img.shape, dtype=np.int32)
    img = img.astype(np.int32)

    # loop over the image
    for y in range(0, h):
        for x in range(0, w):
            # tmp = Y - Cg/2;
            tmp = img[y, x, 0] - (img[y, x, 2] >> 1)

            # G   = Cg + tmp;
            out[y, x, 1] = img[y, x, 2] + tmp

            # B   = tmp - Co/2;
            out[y, x, 0] = tmp - (img[y, x, 1] >> 1)

            # R   = B + Co;
            out[y, x, 2] = out[y, x, 0] + img[y, x, 1]

    return out


def rgb_to_ycocg(img: np.ndarray):
    ccm = np.array([[0.25, 0.5, 0.25], [-0.5, 0, 0.5], [-0.25, 0.5, -0.25]])

    return np.matmul(img, ccm.T)


def ycocg_to_rgb(img: np.ndarray):
    ccm = np.array([[1, -1, -1], [1, 0, 1], [1, 1, -1]])

    return np.matmul(img, ccm.T)


def ycocg_awb(img: np.ndarray):
    h = img.shape[0]
    w = img.shape[1]

    out = np.zeros(shape=img.shape, dtype=np.int32)
    img = img.astype(np.int32)

    y_max = np.max(img[:, :, 0])
    avg_co = np.average(img[:, :, 1])
    avg_cg = np.average(img[:, :, 2])
    print(avg_co)
    print(avg_cg)

    # loop over the image
    for y in range(0, h):
        for x in range(0, w):
            tmp = img[y, x, 0] / y_max
            out[y, x, 1] = img[y, x, 1] - ((avg_co) * tmp * 1.1)
            out[y, x, 2] = img[y, x, 2] - ((avg_cg) * tmp * 1.1)

    out[:, :, 0] = img[:, :, 0]

    print(np.average(out[:, :, 1]))
    print(np.average(out[:, :, 2]))

    return out


def rgb_to_xyz(img: np.ndarray):
    # Matrix([[0.625000000000000, 0.250000000000000, 0.125000000000000], [0.312500000000000, 0.625000000000000, 0.0625000000000000], [0.0625000000000000, 0.125000000000000, 0.812500000000000]])
    ccm = np.array(
        [[0.6250, 0.2500, 0.1250], [0.3125, 0.6250, 0.0625], [0.0625, 0.1250, 0.8125]]
    )

    result = np.matmul(img, ccm.T)

    # result[result > 255] = 255
    # result[result < 0] = 0

    return result


def xyz_to_rgb(img: np.ndarray):
    # Matrix([[2.00000000000000, -0.750000000000000, -0.250000000000000], [-1.00000000000000, 2.00000000000000, 0], [0, -0.250000000000000, 1.25000000000000]])
    ccm = np.array([[2.00, -0.75, -0.25], [-1.00, 2.00, 0], [0, -0.25, 1.25]])

    result = np.matmul(img, ccm.T)

    # result[result > 255] = 255
    # result[result < 0] = 0

    return result


def interpolate(
    x1: float,
    x2: float,
    y1: float,
    y2: float,
    x_offs: int,
    y_offs: int,
    grid_size: int = 64,
):
    x_interp = x1 + (x_offs * (x2 - x1)) / grid_size
    y_interp = y1 + (x_offs * (y2 - y1)) / grid_size

    result = x_interp + (y_offs * (y_interp - x_interp)) / grid_size

    return result


def lto(img: np.ndarray, grid_size: int = 8):
    h = img.shape[0]
    w = img.shape[1]
    grid_h = int(np.floor(h / grid_size))
    grid_w = int(np.floor(w / grid_size))
    # print (grid_h, grid_w)
    min_array = np.zeros((grid_h, grid_w))
    max_array = np.zeros((grid_h, grid_w))
    mean_array = np.zeros((grid_h, grid_w))

    # find min/max for each grid cell
    for y in range(0, grid_h):
        for x in range(0, grid_w):
            min_array[y, x] = np.min(
                img[
                    y * grid_size : (y + 1) * grid_size - 1,
                    x * grid_size : (x + 1) * grid_size - 1,
                ]
            )
            max_array[y, x] = np.max(
                img[
                    y * grid_size : (y + 1) * grid_size - 1,
                    x * grid_size : (x + 1) * grid_size - 1,
                ]
            )
            mean_array[y, x] = np.mean(
                img[
                    y * grid_size : (y + 1) * grid_size - 1,
                    x * grid_size : (x + 1) * grid_size - 1,
                ]
            )

    # print(min_array)
    # print(max_array)

    # max_array = np.linspace(0, 255, 49)
    # max_array = np.reshape(max_array, (7, 7))

    # interpolate for every pixel
    min_img = np.zeros(img.shape)
    max_img = np.zeros(img.shape)
    mean_img = np.zeros(img.shape)
    for y in range(0, h):
        for x in range(0, w):
            x_offs: int = (x - int(grid_size / 2)) % grid_size
            y_offs: int = (y - int(grid_size / 2)) % grid_size
            x1 = max(int(np.floor((x - grid_size / 2) / grid_size)), 0)
            x2 = min(int(np.ceil((x - grid_size / 2) / grid_size)), grid_w - 1)
            y1 = max(int(np.floor((y - grid_size / 2) / grid_size)), 0)
            y2 = min(int(np.ceil((y - grid_size / 2) / grid_size)), grid_h - 1)
            min_img[y, x] = interpolate(
                min_array[y1, x1],
                min_array[y1, x2],
                min_array[y2, x1],
                min_array[y2, x2],
                x_offs,
                y_offs,
                grid_size,
            )
            max_img[y, x] = interpolate(
                max_array[y1, x1],
                max_array[y1, x2],
                max_array[y2, x1],
                max_array[y2, x2],
                x_offs,
                y_offs,
                grid_size,
            )
            mean_img[y, x] = interpolate(
                mean_array[y1, x1],
                mean_array[y1, x2],
                mean_array[y2, x1],
                mean_array[y2, x2],
                x_offs,
                y_offs,
                grid_size,
            )
            diff = max_img[y, x] - min_img[y, x]
            if diff < 32:
                # max_img[y, x] += (32-diff)/2
                # min_img[y, x] -= (64-diff)/2
                # min_img[y, x] = max(min_img[y, x], 0.1)
                pass

    cv2.imwrite("min.png", min_img)
    cv2.imwrite("max.png", max_img)
    cv2.imwrite("mean.png", mean_img)
    cv2.imwrite("diff.png", max_img - min_img)

    result = np.zeros(img.shape)
    for y in range(0, h):
        for x in range(0, w):
            result[y, x] = (math.log(img[y, x]) - math.log(min_img[y, x])) / (
                math.log(max_img[y, x]) - math.log(min_img[y, x])
            )

    return np.clip(result, 0, 1) * 255


def gto_simple(rgb: np.ndarray):
    xyz = rgb_to_xyz(rgb)
    # xyz = cv2.cvtColor(rgb, cv2.COLOR_BGR2XYZ)
    Y = xyz[:, :, 1]
    logimg = np.log(Y)

    L1_simple = (logimg - np.min(logimg)) / (np.max(logimg) - np.min(logimg)) * 255

    out_simple = np.zeros(xyz.shape)
    mult_simple = L1_simple / Y
    out_simple[:, :, 0] = mult_simple * xyz[:, :, 0]
    out_simple[:, :, 1] = L1_simple
    out_simple[:, :, 2] = mult_simple * xyz[:, :, 2]

    # rgb_simple = cv2.cvtColor(out_simple, cv2.COLOR_XYZ2BGR)
    rgb_simple = xyz_to_rgb(out_simple)

    return rgb_simple


def bitlog(x: int):
    pass


def mylog(inp: np.ndarray):
    return np.array([bitlog(int(xi)) for xi in inp])


def myexp(inp: np.ndarray):
    pass


def gto_kimkautz(rgb: np.ndarray, c1: float = 3.0, c2: float = 0.5):
    # convert to unsigned integer first
    dynamic_range = np.log2(np.max(rgb)) - np.log2(np.min(rgb))
    print("dynamic_range: ", dynamic_range)
    # RGB to XYZ
    xyz = rgb_to_xyz(rgb)  # once per pixel

    # Log image
    L0 = xyz[:, :, 1]
    logimg = np.log2(L0)  # once per pixel (current + previous frame)
    logmean = np.mean(
        logimg
    )  # once per pixel (previous frame) (add per pixel / divide per frame)
    logmax = np.max(logimg)  # once per pixel (previous frame)
    logmin = np.min(logimg)  # once per pixel (previous frame)

    # Tonemapping
    d0 = logmax - logmin  # once per frame
    sigma = d0 / c1  # once per frame / multiplication / LUT?
    # w = np.exp(-0.5 * np.square(logimg-logmean)/np.square(sigma))   # once per pixel / LUT?
    w = 2 ** (
        -0.5 * np.square(logimg - logmean) / np.square(sigma)
    )  # once per pixel / LUT?

    maxLd = np.log2(256)  # constant
    minLd = np.log2(1)  # constant
    k1 = (maxLd - minLd) / (logmax - logmin)  # once per frame

    k2 = (1 - k1) * w + k1  # once per pixel

    # L1 = np.exp(c2 * k2 * (logimg - logmean) + logmean)             # once per pixel
    L1 = 2 ** (c2 * k2 * (logimg - logmean) + logmean)  # once per pixel
    # L1 = 2 ** (k1 * logimg)

    print("  max img    :", np.max(L0))
    print("  min img    :", np.min(L0))
    print("  d0         :", d0)
    print("  logmax     :", logmax)
    print("  logmin     :", logmin)
    print("  logmean    :", logmean)
    print("  k1         :", k1)
    print("  np.max(k2) :", np.max(k2))
    print("  np.min(k2) :", np.min(k2))
    print("  np.max(w)  :", np.max(w))
    print("  np.min(w)  :", np.min(w))
    print("  c1         :", c1)
    print("  c2         :", c2)
    print("  np.max(L1) :", np.max(L1))
    print("  np.min(L1) :", np.min(L1))

    # Scaling the color components
    out_kimkautz = np.zeros(xyz.shape)
    mult_kimkautz = L1 / L0  # once per pixel / divide
    print("  mult_max   :", np.max(mult_kimkautz))
    print("  mult_min   :", np.min(mult_kimkautz))

    out_kimkautz[:, :, 0] = mult_kimkautz * xyz[:, :, 0]  # once per pixel
    out_kimkautz[:, :, 1] = L1  # nop
    out_kimkautz[:, :, 2] = mult_kimkautz * xyz[:, :, 2]  # once per pixel

    print("  np.max(L1) :", np.max(L1))
    print("  np.min(L1) :", np.min(L1))

    print(" max(out_kimkautz): ", np.max(out_kimkautz))
    print(" min(out_kimkautz): ", np.min(out_kimkautz))

    # XYZ to RGB
    rgb_kimkautz = xyz_to_rgb(out_kimkautz)  # once per pixel

    # Gamma correction
    rgb_kimkautz = rgb_kimkautz ** (0.45)  # once per pixel

    # Contrast stretch
    final_min = np.quantile(rgb_kimkautz, 0.01)  # once per pixel
    final_max = np.quantile(rgb_kimkautz, 0.99)  # once per pixel
    rgb_kimkautz[rgb_kimkautz < final_min] = final_min  # once per pixel
    rgb_kimkautz[rgb_kimkautz > final_max] = final_max  # once per pixel
    print("  final_max  :", final_max)
    print("  final_min  :", final_min)
    rgb_kimkautz = (
        (rgb_kimkautz - final_min) / (final_max - final_min)
    ) * 255  # once per pixel

    print(" max(rgb_kimkautz): ", np.max(rgb_kimkautz))
    print(" min(rgb_kimkautz): ", np.min(rgb_kimkautz))

    return rgb_kimkautz


def gto_drago(rgb: np.ndarray, b: float = 0.84):
    xyz = rgb_to_xyz(rgb)
    # xyz = cv2.cvtColor(rgb, cv2.COLOR_BGR2XYZ)
    Y = xyz[:, :, 1]

    Y = Y - np.min(Y)
    L_av = np.mean(Y)  # once per frame
    L_max = np.max(Y) / L_av  # once per frame
    divider = np.log10(L_max + 1.0)  # once per frame

    L_w = Y / L_av  # per pixel - div or 1/x mult

    interpol = np.log10(2.0 + np.sqrt(np.sqrt(L_w / L_max)) * 8.0)  # per pixel
    L_d = (np.log10(L_w + 1.0)) / (divider * interpol)  # per pixel

    # img_div = img/np.mean(img)
    # b = 2 + 8*np.sqrt(np.sqrt(img_div))
    # L1 = np.log(img + 1) / (np.log10(img_div/max + 1) * np.log(b))

    # print('max(img_div)=', np.max(img_div))
    # print('min(img_div)=', np.min(img_div))

    L1 = L_d * 255

    out_drago = np.zeros(xyz.shape)
    mult_drago = L1 / Y
    out_drago[:, :, 0] = mult_drago * xyz[:, :, 0]
    out_drago[:, :, 1] = L1
    out_drago[:, :, 2] = mult_drago * xyz[:, :, 2]

    rgb_drago = xyz_to_rgb(out_drago)
    # rgb_drago = cv2.cvtColor(out_drago, cv2.COLOR_XYZ2BGR)

    return rgb_drago


def test_colorgain():
    # load image
    cfa = cv2.imread("../dataset/2.png", cv2.IMREAD_UNCHANGED)

    # color gain!
    cfa = colorgain(
        cfa, rgain=1, bgain=2, g0gain=1, g1gain=1, code=cv2.COLOR_BayerRGGB2BGR
    )

    # process & write image
    rgb = cv2.cvtColor(cfa.astype(np.uint16), cv2.COLOR_BayerBG2BGR)
    tmo = cv2.createTonemapReinhard(gamma=2.2)
    rgb = tmo.process(rgb.astype(np.float32))
    cv2.imwrite("colorgain2.png", rgb * 255)


def test_rgb_to_ycocg():
    # load image
    cfa = cv2.imread("../dataset/2.png", cv2.IMREAD_UNCHANGED)

    rgb = cv2.cvtColor(cfa.astype(np.uint16), cv2.COLOR_BayerBG2BGR)

    ycocg = rgb_to_ycocg(rgb)

    # y = (ycocg[:,:,0]/np.max(ycocg[:,:,0])).astype(np.float32)
    # co = ((ycocg[:,:,1] + np.abs(np.min(ycocg[:,:,1])))/(np.max(ycocg[:,:,1])-np.min(ycocg[:,:,1]))).astype(np.float32)
    # cg = ((ycocg[:,:,2] + np.abs(np.min(ycocg[:,:,2])))/(np.max(ycocg[:,:,2])-np.min(ycocg[:,:,2]))).astype(np.float32)

    # print(rgb)
    # print(ycocg[:,:,2])
    # y = tmo.process(y.astype(np.float32))

    # cv2.imwrite('ycocg-y.png', y*255)
    # cv2.imwrite('ycocg-co.png', co*255)
    # cv2.imwrite('ycocg-cg.png', cg*255)

    # ycocg2 = ycocg_awb(ycocg)

    rgb2 = ycocg_to_rgb(ycocg).astype(np.uint16)

    tmo = cv2.createTonemapReinhard(gamma=2.2)
    rgb3 = tmo.process(rgb2.astype(np.float32))
    orig = tmo.process(rgb.astype(np.float32))

    cv2.imwrite("orig.png", orig * 255)
    cv2.imwrite("ycocg2rgb.png", rgb3 * 255)


def test_lto():
    cfa = cv2.imread("../dataset/12.png", cv2.IMREAD_UNCHANGED)
    rgb = cv2.cvtColor(cfa.astype(np.uint16), cv2.COLOR_BayerBG2BGR)
    ycocg = rgb_to_ycocg(rgb)
    y_lto = lto(ycocg[:, :, 0])
    cg_div = ycocg[:, :, 1] / ycocg[:, :, 0]
    co_div = ycocg[:, :, 2] / ycocg[:, :, 0]

    cv2.imwrite("y.png", ycocg[:, :, 0])
    cv2.imwrite("co.png", np.abs(ycocg[:, :, 1]))
    cv2.imwrite("cg.png", np.abs(ycocg[:, :, 2]))
    cv2.imwrite("y_lto.png", y_lto)
    ycocg[:, :, 0] = y_lto
    ycocg[:, :, 1] = cg_div * y_lto
    ycocg[:, :, 2] = co_div * y_lto
    rgb2 = ycocg_to_rgb(ycocg)
    cv2.imwrite("rgb_lto_2.png", rgb2)

    # RGB test
    rgb3 = rgb
    rgb3[:, :, 0] = lto(rgb[:, :, 0])
    rgb3[:, :, 1] = lto(rgb[:, :, 1])
    rgb3[:, :, 2] = lto(rgb[:, :, 2])
    cv2.imwrite("rgb_direct_lto.png", rgb3.astype(np.uint8))

    # RGB Luminance test
    rgb[:, :, 0] = (rgb[:, :, 0] / ycocg[:, :, 0]) * y_lto
    rgb[:, :, 1] = (rgb[:, :, 1] / ycocg[:, :, 0]) * y_lto
    rgb[:, :, 2] = (rgb[:, :, 2] / ycocg[:, :, 0]) * y_lto
    cv2.imwrite("rgb_lum_lto.png", rgb.astype(np.uint8))

    # CFA test
    cfa = colorgain(
        cfa, rgain=1.256, bgain=1.05, g0gain=1, g1gain=1, code=cv2.COLOR_BayerRGGB2BGR
    )
    cfa2 = lto(cfa)
    print(np.max(cfa2))
    print(np.min(cfa2))
    rgb_cfa = cv2.cvtColor(cfa2.astype(np.uint16), cv2.COLOR_BayerBG2BGR)
    cv2.imwrite("rgb_cfa_lto.png", rgb_cfa.astype(np.uint8))


def test_gto():
    # cfa = cv2.imread('../dataset/1.png', cv2.IMREAD_UNCHANGED)
    # rgb = cv2.cvtColor(cfa.astype(np.uint16), cv2.COLOR_BayerBG2BGR)
    rgb = cv2.imread("../dataset/memorial.exr", cv2.IMREAD_UNCHANGED)
    # rgb = cv2.imread('../dataset/AtriumNight.exr', cv2.IMREAD_UNCHANGED)
    # rgb = cv2.imread('../dataset/AtriumMorning.exr', cv2.IMREAD_UNCHANGED)
    # rgb = cv2.imread('../dataset/HotelRoom.exr', cv2.IMREAD_UNCHANGED)
    # rgb = cv2.imread('../dataset/NapaValley.exr', cv2.IMREAD_UNCHANGED)

    drago = gto_drago(rgb)
    cv2.imwrite("gto_result_drago.png", drago.astype(np.uint8))

    kimkautz = gto_kimkautz(rgb)
    cv2.imwrite("gto_result_kimkautz.png", kimkautz.astype(np.uint8))

    simple = gto_simple(rgb)
    cv2.imwrite("gto_result_simple.png", simple.astype(np.uint8))

    # cv2.imwrite('gto_L1_drago.png', L1_drago.astype(np.uint8))
    # cv2.imwrite('gto_L1_kimkautz.png', L1_kimkautz.astype(np.uint8))
    # cv2.imwrite('gto_L1_simple.png', L1_simple.astype(np.uint8))
    # print('Drago max: ', np.max(L1_drago))
    # print('Drago min: ', np.min(L1_drago))
    # print('KimKautz max: ', np.max(L1_kimkautz))
    # print('KimKautz min: ', np.min(L1_kimkautz))
    # print('Simple max: ', np.max(L1_simple))
    # print('Simple min: ', np.min(L1_simple))


if __name__ == "__main__":
    # test_colorgain()
    # test_rgb_to_ycocg()
    # test_lto()
    test_gto()
