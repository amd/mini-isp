/*
 * SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All
 * rights reserved. SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen
 * (AMD)
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Mini-ISP V4L2 subdevice driver
 *
 */

#include <linux/clk.h>
#include <linux/io.h>
#include <linux/log2.h>
#include <linux/minmax.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/property.h>

#include <media/media-entity.h>
#include <media/v4l2-subdev.h>

#define MINI_ISP_PAD_SINK 0
#define MINI_ISP_PAD_SOURCE 1
#define MINI_ISP_NUM_PADS 2

#define MINI_ISP_BORDER 2

#define MINI_ISP_MIN_SIZE 32
#define MINI_ISP_DEF_WIDTH (1920 + 2 * MINI_ISP_BORDER)
#define MINI_ISP_DEF_HEIGHT (1080 + 2 * MINI_ISP_BORDER)

struct mini_isp_bayer_format {
	u32 bits;
	/* Indexed by xlnx,cfa-orientation: BG, GB, GR, RG */
	u32 codes[4];
};

static const struct mini_isp_bayer_format mini_isp_bayer_formats[] = {
	{ 8,
	  { MEDIA_BUS_FMT_SBGGR8_1X8, MEDIA_BUS_FMT_SGBRG8_1X8,
	    MEDIA_BUS_FMT_SGRBG8_1X8, MEDIA_BUS_FMT_SRGGB8_1X8 } },
	{ 10,
	  { MEDIA_BUS_FMT_SBGGR10_1X10, MEDIA_BUS_FMT_SGBRG10_1X10,
	    MEDIA_BUS_FMT_SGRBG10_1X10, MEDIA_BUS_FMT_SRGGB10_1X10 } },
	{ 12,
	  { MEDIA_BUS_FMT_SBGGR12_1X12, MEDIA_BUS_FMT_SGBRG12_1X12,
	    MEDIA_BUS_FMT_SGRBG12_1X12, MEDIA_BUS_FMT_SRGGB12_1X12 } },
	{ 14,
	  { MEDIA_BUS_FMT_SBGGR14_1X14, MEDIA_BUS_FMT_SGBRG14_1X14,
	    MEDIA_BUS_FMT_SGRBG14_1X14, MEDIA_BUS_FMT_SRGGB14_1X14 } },
	{ 16,
	  { MEDIA_BUS_FMT_SBGGR16_1X16, MEDIA_BUS_FMT_SGBRG16_1X16,
	    MEDIA_BUS_FMT_SGRBG16_1X16, MEDIA_BUS_FMT_SRGGB16_1X16 } },
};

struct mini_isp_rgb_format {
	u32 bits;
	u32 code;
};

static const struct mini_isp_rgb_format mini_isp_rgb_formats[] = {
	{ 8, MEDIA_BUS_FMT_RBG888_1X24 },
	{ 10, MEDIA_BUS_FMT_RBG101010_1X30 },
	{ 12, MEDIA_BUS_FMT_RBG121212_1X36 },
	{ 16, MEDIA_BUS_FMT_RBG161616_1X48 },
};

struct mini_isp {
	struct device *dev;
	void __iomem *regs;
	struct v4l2_subdev sd;
	struct media_pad pads[MINI_ISP_NUM_PADS];
	struct mutex lock;
	struct v4l2_mbus_framefmt formats[MINI_ISP_NUM_PADS];

	u32 sink_code;
	u32 source_code;
	u32 max_width;
	u32 ppc;
};

static inline struct mini_isp *to_mini_isp(struct v4l2_subdev *sd)
{
	return container_of(sd, struct mini_isp, sd);
}

static void mini_isp_adjust_sink(struct mini_isp *isp,
				 struct v4l2_mbus_framefmt *fmt)
{
	fmt->code = isp->sink_code;
	fmt->width = clamp_t(u32, round_down(fmt->width, isp->ppc),
			     MINI_ISP_MIN_SIZE, isp->max_width);
	fmt->height =
		clamp_t(u32, fmt->height, MINI_ISP_MIN_SIZE, isp->max_width);
	fmt->field = V4L2_FIELD_NONE;
}

static void mini_isp_source_from_sink(struct mini_isp *isp,
				      const struct v4l2_mbus_framefmt *sink,
				      struct v4l2_mbus_framefmt *source)
{
	*source = *sink;
	source->code = isp->source_code;
	source->width = sink->width - 2 * MINI_ISP_BORDER;
	source->height = sink->height - 2 * MINI_ISP_BORDER;
}

static void mini_isp_init_formats(struct mini_isp *isp,
				  struct v4l2_mbus_framefmt *sink,
				  struct v4l2_mbus_framefmt *source)
{
	*sink = (struct v4l2_mbus_framefmt){
		.width = MINI_ISP_DEF_WIDTH,
		.height = MINI_ISP_DEF_HEIGHT,
		.colorspace = V4L2_COLORSPACE_SRGB,
	};
	mini_isp_adjust_sink(isp, sink);
	mini_isp_source_from_sink(isp, sink, source);
}

static struct v4l2_mbus_framefmt *
mini_isp_get_pad_format(struct mini_isp *isp, struct v4l2_subdev_state *state,
			unsigned int pad, u32 which)
{
	if (which == V4L2_SUBDEV_FORMAT_TRY)
		return v4l2_subdev_state_get_format(state, pad);

	return &isp->formats[pad];
}

static int mini_isp_enum_mbus_code(struct v4l2_subdev *sd,
				   struct v4l2_subdev_state *state,
				   struct v4l2_subdev_mbus_code_enum *code)
{
	struct mini_isp *isp = to_mini_isp(sd);

	if (code->index)
		return -EINVAL;

	code->code = code->pad == MINI_ISP_PAD_SINK ? isp->sink_code :
						      isp->source_code;
	return 0;
}

static int mini_isp_enum_frame_size(struct v4l2_subdev *sd,
				    struct v4l2_subdev_state *state,
				    struct v4l2_subdev_frame_size_enum *fse)
{
	struct mini_isp *isp = to_mini_isp(sd);
	u32 shrink = fse->pad == MINI_ISP_PAD_SINK ? 0 : 2 * MINI_ISP_BORDER;
	u32 code = fse->pad == MINI_ISP_PAD_SINK ? isp->sink_code :
						   isp->source_code;

	if (fse->index || fse->code != code)
		return -EINVAL;

	fse->min_width = MINI_ISP_MIN_SIZE - shrink;
	fse->max_width = isp->max_width - shrink;
	fse->min_height = MINI_ISP_MIN_SIZE - shrink;
	fse->max_height = isp->max_width - shrink;

	return 0;
}

static int mini_isp_get_format(struct v4l2_subdev *sd,
			       struct v4l2_subdev_state *state,
			       struct v4l2_subdev_format *fmt)
{
	struct mini_isp *isp = to_mini_isp(sd);

	mutex_lock(&isp->lock);
	fmt->format =
		*mini_isp_get_pad_format(isp, state, fmt->pad, fmt->which);
	mutex_unlock(&isp->lock);

	return 0;
}

static int mini_isp_set_format(struct v4l2_subdev *sd,
			       struct v4l2_subdev_state *state,
			       struct v4l2_subdev_format *fmt)
{
	struct mini_isp *isp = to_mini_isp(sd);
	struct v4l2_mbus_framefmt *sink, *source;

	mutex_lock(&isp->lock);

	sink = mini_isp_get_pad_format(isp, state, MINI_ISP_PAD_SINK,
				       fmt->which);
	source = mini_isp_get_pad_format(isp, state, MINI_ISP_PAD_SOURCE,
					 fmt->which);

	if (fmt->pad == MINI_ISP_PAD_SINK) {
		*sink = fmt->format;
		mini_isp_adjust_sink(isp, sink);
		mini_isp_source_from_sink(isp, sink, source);
	}

	fmt->format = fmt->pad == MINI_ISP_PAD_SINK ? *sink : *source;

	mutex_unlock(&isp->lock);

	return 0;
}

static int mini_isp_init_state(struct v4l2_subdev *sd,
			       struct v4l2_subdev_state *state)
{
	mini_isp_init_formats(
		to_mini_isp(sd),
		v4l2_subdev_state_get_format(state, MINI_ISP_PAD_SINK),
		v4l2_subdev_state_get_format(state, MINI_ISP_PAD_SOURCE));
	return 0;
}

static const struct v4l2_subdev_pad_ops mini_isp_pad_ops = {
	.enum_mbus_code = mini_isp_enum_mbus_code,
	.enum_frame_size = mini_isp_enum_frame_size,
	.get_fmt = mini_isp_get_format,
	.set_fmt = mini_isp_set_format,
};

static const struct v4l2_subdev_ops mini_isp_ops = {
	.pad = &mini_isp_pad_ops,
};

static const struct v4l2_subdev_internal_ops mini_isp_internal_ops = {
	.init_state = mini_isp_init_state,
};

static const struct media_entity_operations mini_isp_media_ops = {
	.link_validate = v4l2_subdev_link_validate,
};

static int mini_isp_parse_dt(struct mini_isp *isp)
{
	struct device *dev = isp->dev;
	u32 cfa, pixel_bits, component_bits, ppc;
	unsigned int i;

	if (device_property_read_u32(dev, "xlnx,cfa-orientation", &cfa) ||
	    device_property_read_u32(dev, "xlnx,pixel-bit-width",
				     &pixel_bits) ||
	    device_property_read_u32(dev, "xlnx,component-bit-width",
				     &component_bits) ||
	    device_property_read_u32(dev, "xlnx,max-resolution",
				     &isp->max_width) ||
	    device_property_read_u32(dev, "xlnx,pixel-per-cycle", &ppc))
		return dev_err_probe(
			dev, -EINVAL,
			"missing xlnx,* IP parameter properties\n");

	if (cfa >= ARRAY_SIZE(mini_isp_bayer_formats[0].codes))
		return dev_err_probe(dev, -EINVAL,
				     "invalid xlnx,cfa-orientation %u\n", cfa);

	for (i = 0; i < ARRAY_SIZE(mini_isp_bayer_formats); i++)
		if (mini_isp_bayer_formats[i].bits == pixel_bits)
			isp->sink_code = mini_isp_bayer_formats[i].codes[cfa];
	if (!isp->sink_code)
		return dev_err_probe(dev, -EINVAL,
				     "unsupported xlnx,pixel-bit-width %u\n",
				     pixel_bits);

	for (i = 0; i < ARRAY_SIZE(mini_isp_rgb_formats); i++)
		if (mini_isp_rgb_formats[i].bits == component_bits)
			isp->source_code = mini_isp_rgb_formats[i].code;
	if (!isp->source_code)
		return dev_err_probe(
			dev, -EINVAL,
			"unsupported xlnx,component-bit-width %u\n",
			component_bits);

	if (!is_power_of_2(ppc) || ppc > 8)
		return dev_err_probe(dev, -EINVAL,
				     "invalid xlnx,pixel-per-cycle %u\n", ppc);

	isp->ppc = ppc;

	if (isp->max_width < MINI_ISP_MIN_SIZE)
		return dev_err_probe(dev, -EINVAL,
				     "invalid xlnx,max-resolution %u\n",
				     isp->max_width);

	return 0;
}

static int mini_isp_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct v4l2_subdev *sd;
	struct mini_isp *isp;
	struct clk *clk;
	int ret;

	isp = devm_kzalloc(dev, sizeof(*isp), GFP_KERNEL);
	if (!isp)
		return -ENOMEM;

	isp->dev = dev;

	isp->regs = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(isp->regs))
		return PTR_ERR(isp->regs);

	clk = devm_clk_get_enabled(dev, NULL);
	if (IS_ERR(clk))
		return dev_err_probe(dev, PTR_ERR(clk),
				     "failed to get clock\n");

	ret = mini_isp_parse_dt(isp);
	if (ret)
		return ret;

	ret = devm_mutex_init(dev, &isp->lock);
	if (ret)
		return ret;

	mini_isp_init_formats(isp, &isp->formats[MINI_ISP_PAD_SINK],
			      &isp->formats[MINI_ISP_PAD_SOURCE]);

	sd = &isp->sd;
	v4l2_subdev_init(sd, &mini_isp_ops);
	sd->internal_ops = &mini_isp_internal_ops;
	sd->dev = dev;
	sd->owner = THIS_MODULE;
	sd->flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	strscpy(sd->name, dev_name(dev), sizeof(sd->name));
	v4l2_set_subdevdata(sd, isp);

	sd->entity.function = MEDIA_ENT_F_PROC_VIDEO_ISP;
	sd->entity.ops = &mini_isp_media_ops;
	isp->pads[MINI_ISP_PAD_SINK].flags = MEDIA_PAD_FL_SINK;
	isp->pads[MINI_ISP_PAD_SOURCE].flags = MEDIA_PAD_FL_SOURCE;

	ret = media_entity_pads_init(&sd->entity, MINI_ISP_NUM_PADS, isp->pads);
	if (ret)
		return ret;

	platform_set_drvdata(pdev, isp);

	ret = v4l2_async_register_subdev(sd);
	if (ret) {
		media_entity_cleanup(&sd->entity);
		return dev_err_probe(dev, ret, "failed to register subdev\n");
	}

	dev_info(dev, "Mini-ISP: sink 0x%04x, source 0x%04x, max width %u\n",
		 isp->sink_code, isp->source_code, isp->max_width);

	return 0;
}

static void mini_isp_remove(struct platform_device *pdev)
{
	struct mini_isp *isp = platform_get_drvdata(pdev);

	v4l2_async_unregister_subdev(&isp->sd);
	media_entity_cleanup(&isp->sd.entity);
}

static const struct of_device_id mini_isp_of_match[] = {
	{ .compatible = "xlnx,mini-isp-0.1" },
	{}
};
MODULE_DEVICE_TABLE(of, mini_isp_of_match);

static struct platform_driver mini_isp_driver = {
    .driver =
        {
            .name = "mini-isp",
            .of_match_table = mini_isp_of_match,
        },
    .probe = mini_isp_probe,
    .remove = mini_isp_remove,
};
module_platform_driver(mini_isp_driver);

MODULE_AUTHOR("Timor Knudsen <timor.knudsen@amd.com>");
MODULE_DESCRIPTION("Mini-ISP V4L2 subdevice driver");
MODULE_LICENSE("GPL");
